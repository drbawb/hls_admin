defmodule HlsAdmin.FfmpegServer do
  use GenServer
  require Logger

  @moduledoc """
  The `FfmpegServer` manages a group of (OS) FFMPEG processes
  that perform the transcoding of a video input into one
  or more HLS streams.
  """

  #
  # Client API
  #

  @doc """
  Begins a transcoding job if one is not already running.
  This will transition the server into the `:running` state.

  ## Errors

  Returns `{:error, :stream_already_started}` if the stream is
  currently running.
  """
  def start_stream(stream_config) do
    GenServer.call(__MODULE__, {:start, stream_config})
  end

  @doc """
  Stops the currently running transcoding job(s).
  NOTE: This is a no-op if the server is already in the `:stopped` state.
  """
  def stop_stream() do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Uses `ffprobe` to extract a list of available streams from the
  provided media located at `path`. This information can be used to construct
  the necessary arguments to run a transcoding job via `start_stream(...)`
  for that particular path.
  """
  def probe_stream(path) do
    GenServer.call(__MODULE__, {:probe, path})
  end

  @doc "Returns the current server runlevel, one of: `:running | :stopping | :stopped`."
  def runlevel() do
    GenServer.call(__MODULE__, :runlevel)
  end

  @doc "Returns ffmpeg server status block."
  def status() do
    GenServer.call(__MODULE__, :status)
  end


  #
  # Callbacks
  #

  def init(_state) do
    config_block = Application.fetch_env!(:hls_admin, HlsAdmin.FfmpegServer)
    Logger.info "Starting FFMPEG server process: #{inspect config_block}"


    {:ok, %{
      runlevel: :stopped,
      root: config_block[:hls_root],
      playlist: config_block[:playlist],
      pid_waits: [],
    }}
  end

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  def handle_call(:status, _from, state) do
    {:ok, server_time} = 
      Timex.local 
      |> Timex.format("{YYYY}-{0M}-{0D} {0h12}:{0m}:{0s} {AM}")

    status_block = %{
      time: server_time,
      runlevel: state.runlevel,
      ffmpeg_procs_alive: num_running_tasks(state),
    }

    {:reply, status_block, state}
  end

  def handle_call({:start, config}, _from, state = %{runlevel: :stopped}) do
    alias HlsAdmin.FfmpegServer.ProfSetting

    :ok = write_playlist(state)

    # TODO: probably take this in as an arg
    levels = [
      %ProfSetting{level: "low", bitrate_audio: "64k", bitrate_video: "768k"},
      %ProfSetting{level: "mid", bitrate_audio: "96k", bitrate_video: "2M"},
      %ProfSetting{level: "src", bitrate_audio: "128k", bitrate_video: "4M"}
    ]

    pid_parent = self()
    procs = for level <- levels do
      args = build_ffmpeg_args(state, config, level)
      opts = [out: :string, err: :string, in: :receive]
      proc = Porcelain.spawn("ffmpeg", args, opts)

      # wait for task to be done
      awaiting_pid = spawn(fn ->
        case Porcelain.Process.await(proc) do
          {:ok, shell_resp} ->
            send(pid_parent, {:done, self(), shell_resp})

          {:error, :noproc} ->
            send(pid_parent, {:done, self(), proc})
        end
      end)

      {awaiting_pid, proc}
    end

    pid_wait_states =
      procs
      |> Enum.map(fn {awaiter, shell} -> {awaiter, {:running, shell}} end)
      |> Map.new()


    state =
      state
      |> Map.put(:pid_waits, pid_wait_states)
      |> Map.put(:runlevel, :running)
      |> Map.put(:config, %{mux: config, profiles: levels})

    Phoenix.PubSub.broadcast HlsAdmin.PubSub, "ffmpeg:status_change", {:ffmpeg, state.runlevel}
    {:reply, {:ok, procs}, %{state | pid_waits: pid_wait_states}}
  end

  def handle_call({:start, path}, _from, state) do
    {:reply, {:error, :stream_already_started}, state}
  end

  def handle_call(:stop, _from, state) do
    for {pid, proc} <- state.pid_waits do
      case proc do
        {:running, shell_pid} ->
          # HACK: we have to send input to get `goon` to pump its
          #       input loop and process the pending SIGTERM ...
          Logger.warn "terminating #{inspect(shell_pid)}"
          Porcelain.Process.signal(shell_pid, 15)
          Porcelain.Process.send_input(shell_pid, "")

        proc_status ->
          Logger.warn "process in unexpected status: #{inspect proc_status}"
      end
    end

    {:reply, :ok, state}
  end

  def handle_call({:probe, path}, _from, state) do
    probe = with {:ok, ffprobe_json} <- run_ffprobe(path),
                 {:ok, ffprobe_body} <- Jason.decode(ffprobe_json),
                 {:ok, ffprobe_resp} <- parse_ffprobe_result(ffprobe_body)
    do
      {:ok, ffprobe_resp}
    else
      err -> {:error, err}
    end

    {:reply, probe, state}
  end

  # await ffmpeg processes and clean up when they're done ...
  def handle_info({:done, pid, proc}, state) do
    new_state =
      state
      |> cleanup_waiting_pid(pid, proc)
      |> update_runlevel()
      |> cleanup_stopping()

    {:noreply, new_state}
  end

  #
  # Implementation
  #

  defp cleanup_waiting_pid(state, pid, proc) do
    status = Map.get(proc, :status, :killed)

    new_waitlist =
      state.pid_waits
      |> Map.put(pid, {:exit, status})

    %{state | pid_waits: new_waitlist}
  end

  defp cleanup_stopping(state = %{runlevel: :stopping}) do
    Logger.debug "stopping ffmpeg server"
    old_playlist = Path.join(state.root, "#{state.playlist}.m3u8")
    {old_config, state} = Map.pop(state, :config)

    Logger.debug "cleaning up master playlist: #{inspect old_playlist}"
    File.rm(old_playlist)

    for profile <- old_config.profiles do
      profile_dir = Path.join(state.root, "#{state.playlist}_#{profile.level}")
      Logger.debug "cleaning up profile dir: #{inspect profile_dir}"

      files =
        Path.join(profile_dir, "*.{ts,m3u8}")
        |> Path.wildcard()
        |> Enum.map(fn el -> File.rm(el) end)
    end

    Phoenix.PubSub.broadcast HlsAdmin.PubSub, "ffmpeg:status_change", {:ffmpeg, :stopped}
    %{state | runlevel: :stopped}
  end

  defp cleanup_stopping(state), do: state

  defp update_runlevel(state) do
    num_running = num_running_tasks(state)
    new_runlevel = if num_running > 0, do: :running, else: :stopping

    Phoenix.PubSub.broadcast HlsAdmin.PubSub, "ffmpeg:status_change", {:ffmpeg, new_runlevel}
    %{state | runlevel: new_runlevel}
  end

  defp num_running_tasks(state) do
    live_ents = for {_pid, {status, _}} <- state.pid_waits do
      status == :running
    end

    num_running =
      live_ents
      |> Enum.filter(fn el -> el end)
      |> Enum.count()
  end

  defp write_playlist(state) do
    pl_path = Path.join(state.root, "#{state.playlist}.m3u8")
    {:ok, file} = File.open(pl_path, [:write])

    # write header
	  :ok = IO.write(file, "#EXTM3U\n")
    :ok = IO.write(file, "#EXT-X-VERSION:3\n")

    # level: src
	  :ok = IO.write(file, "#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080\n")
    :ok = IO.write(file, "cdn00_src/index.m3u8\n")

    # level: mid
	  :ok = IO.write(file, "#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080\n")
    :ok = IO.write(file, "cdn00_mid/index.m3u8\n")

    # level: low
	  :ok = IO.write(file, "#EXT-X-STREAM-INF:BANDWIDTH=960000,RESOLUTION=1920x1080\n")
    :ok = IO.write(file, "cdn00_low/index.m3u8\n")

    File.close(file)
  end

  defp build_ffmpeg_args(state, mux, prof) do
    level_name = "#{state.playlist}_#{prof.level}"
    seg_path = Path.join([state.root, level_name, "index.m3u8"])
    seg_name = Path.join([state.root, level_name, "%03d.ts"])

    ffmpeg_av_args = [
      "-y",
      "-re",
      "-i", mux.av_path,
      "-b:v", prof.bitrate_video,
      "-c:v", "libx264",
      "-x264opts", "keyint=300:no-scenecut",
      "-pix_fmt" ,"yuv420p",
      "-profile:v", "main",
      "-r", "30",
      "-b:a", prof.bitrate_audio,
      "-c:a", "aac",
      "-preset", "veryfast",
      "-map", "0:#{mux.idx_v}",
      "-map", "0:#{mux.idx_a}",
    ]

    # TODO: -vf subtitles=<path>:si=<idx>
    ffmpeg_st_args = case mux.st_path do
      nil -> []
      idx -> 
        ["-vf", mux.st_path, mux.idx_s]
    end

    ffmpeg_hls_args = [
      "-hls_list_size", "10",
      "-hls_time", "10",
      "-hls_flags", "delete_segments",
      "-hls_segment_filename", seg_name,
      seg_path
    ]

    ffmpeg_args = ffmpeg_av_args ++ ffmepg_st_args ++ ffmpeg_hls_args
  end

  defp run_ffprobe(path) do
    case System.cmd("ffprobe", [
      "-of", "json",
      "-loglevel", "quiet",
      "-show_format",
      "-show_streams",
      path
    ]) do
      {ffprobe_resp, 0} -> {:ok, ffprobe_resp}
      {_stdout, err} -> {:error, [:bad_exit_code, err]}
    end
  end

  defp parse_ffprobe_result(result) do
    streams =
      Enum.map(result["streams"], &_parse_stream/1)
      |> Enum.reject(fn el -> is_nil(el) end)
      |> Enum.group_by(
        fn [tag,_] -> tag end,
        fn [_,streams] -> streams end)

    {:ok, streams}
  end

  defp _parse_stream(stream) do
    case stream["codec_type"] do
      "video"      -> _parse_video(stream)
      "audio"      -> _parse_audio(stream)
      "subtitle"   -> _parse_subtitle(stream)

      codec_type ->
        Logger.warn "ignoring unknown codec ty: #{codec_type}"
        nil

    end
  end

  defp _parse_audio(stream) do
    codec_name = stream["codec_name"]
    codec_idx  = stream["index"]
    codec_lang = stream["tags"]["language"]
    codec_title = stream["tags"]["title"]

    [:audio, %{
      idx:   codec_idx,
      name:  codec_name,
      lang:  codec_lang,
      title: codec_title,
    }]
  end

  defp _parse_subtitle(stream) do
    codec_name  = stream["codec_name"]
    codec_idx   = stream["index"]
    codec_lang  = stream["tags"]["language"]
    codec_title = stream["tags"]["title"]

    [:subtitle, %{
      idx:   codec_idx,
      name:  codec_name,
      lang:  codec_lang,
      title: codec_title,
    }]

  end

  defp _parse_video(stream) do
    codec_name = stream["codec_name"]
    codec_idx  = stream["index"]
    codec_lang = stream["tags"]["language"]

    [:video, %{
      idx:  codec_idx,
      name: codec_name,
      lang: codec_lang,
    }]
  end

end
