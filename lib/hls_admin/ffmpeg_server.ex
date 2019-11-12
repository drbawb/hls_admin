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
  Starts the stream coordination server process w/ the same name
  as this module. `opts` should be a keyword list containing initialization
  parameters for the stream server process.

  The following parameters are supported:

  - `{:hls_root, Path.t()}`: the location where HLS segments & playlists
    will be output by the child FFmpeg processes.

  - `{:playlist, String.t()}`: a prefix which is prepended to the names
    of playlists associated with this stream.

  While the server is in the `:running` state it will create the following
  file structure in the path specified at `:hls_root`:

  - `<playlist>.m3u8`: master playlist containing stream definitions for
    three quality levels: `src`, `mid`, and `low`.

  - `<playlist>_<level>/`: sub-directories containing current playlists and
    MPEG-TS segments for each quality level.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Begins a transcoding job if one is not already running.
  This will transition the server into the `:running` state.

  Note that the server will overwrite existing playlists and directories
  matching the configured `:hls_root` and `:playlist` settings. See the
  documentaitn for `start_link/1` for additional details on the files &
  folders which will be managed by this process upon starting a stream.

  If the stream is allowed to run to completion the server will enter a
  special `:stopping` state and wait approximately 30 before running any
  clean-up handlers. This gives clients a chance to catch-up on downloading
  files for the "final playlist". See `stop_stream/0` for details on what
  happens once this timeout has elapsed.

  The `stream_config` parameter must be of the type `FfmpegServer.MuxSetting`.
  This parameter directs the stream server to a media file, an optional
  subtitle file, and (in the case of multiple tracks) selects an audio,
  video, and subtitle stream to use.

  ## Errors

  Returns `{:error, :stream_already_started}` if the stream is
  currently running. The previously running stream will remain
  running until it is stopped or the `FfmpegServer` process is killed.
  """
  def start_stream(stream_config) do
    GenServer.call(__MODULE__, {:start, stream_config})
  end

  @doc """
  Stops the currently running transcoding job(s). Any FFmpeg processes
  associated with the stream will be killed, and their associated playlists
  and MPEG-TS files will immediately be removed from the `:hls_root` directory.

  After this method has returned the server will have transitioned to the
  `:stopped` state -- at this time it will be ready to accept new transcoding
  jobs via the `start_stream/1` function.

  _Note: This is a no-op if the server is already in the `:stopped` state._
  """
  def stop_stream() do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Uses `ffprobe` to extract a list of available streams from the
  provided media located at `path`. This information can be used to construct
  the necessary arguments to run a transcoding job via `start_stream(...)`
  for that particular path.

  This is useful for extracting information from media files in order to build
  the `stream_config` parameter needed to call `start_stream/1`.
  """
  def probe_stream(path) do
    GenServer.call(__MODULE__, {:probe, path})
  end

  @doc """
  Returns the current server runlevel, which is one of the following
  values based on previously called functions:

  - `:running`: The server is actively creating the HLS streams in the
    configured playlist directory.

  - `:stopping`: The server has run out of input, all transcoding jobs
    have finished, and the server is momentarily paused before cleaning
    up the HLS playlist directory.

  - `:stopped`: If the server has been started previously: the playlist
    directory has been cleaned up and all transcoding jobs have been stopped.
  """
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

  @impl true
  def init(opts \\ []) when is_list(opts) do
    hls_root = Keyword.pop(opts, :hls_root)
    playlist = Keyword.pop(opts, :playlist)

    if is_nil(hls_root) do
      raise ArgumentError, "FfmpegServer requires a working directory, but `:hls_root` was nil."
    end

    if is_nil(playlist) do
      raise ArgumentError, "FfmpegServer requires a playlist prefix, but `:playlist` was nil."
    end

    Logger.info "Starting FFMPEG server process w/ configuration: #{inspect opts}"

    {:ok, %{
      runlevel: :stopped,
      is_killed: false,

      root: hls_root,
      playlist: playlist,
      pid_waits: [],
    }}
  end

  @impl true
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

  @impl true
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
      {:ok, proc} = Lacca.start("ffmpeg", args)

      # wait for task to be done
      #
      # loop until it's not alive and then inform the
      # server that the awaiter task (self()) and process (proc)
      # have died...
      #
      awaiting_pid = spawn(fn ->
        Logger.info "waiting from pid #{inspect self()}"
        loop_waiting_for_death(proc)

        Logger.info "done waiting from pid #{inspect self()}"
        send(pid_parent, {:done, self(), proc})
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

  @impl true
  def handle_call({:start, path}, _from, state) do
    {:reply, {:error, :stream_already_started}, state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    for {pid, proc} <- state.pid_waits do
      case proc do
        {:running, shell_pid} ->
          # HACK: we have to send input to get `goon` to pump its
          #       input loop and process the pending SIGTERM ...
          Logger.warn "terminating #{inspect(shell_pid)}"
          Lacca.kill(shell_pid)

        proc_status ->
          Logger.warn "process in unexpected status: #{inspect proc_status}"
      end
    end

    {:reply, :ok, %{state | is_killed: true}}
  end

  @impl true
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

  @impl true
  def handle_info({:done, pid, proc}, state) do
    # sent ~30s after all ffmpeg processes have died of natural causes

    new_state =
      state
      |> cleanup_waiting_pid(pid, proc)
      |> update_runlevel()
      |> cleanup_stopping()

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_complete, state) do
    # reinit state after we've cleaned up the dead ffmpeg procs
    {:noreply, %{state | runlevel: :stopped, is_killed: false}}
  end

  #
  # Implementation Details
  #

  defp cleanup_waiting_pid(state, pid, proc) do
    new_waitlist =
      state.pid_waits
      |> Map.put(pid, {:exit, proc})

    %{state | pid_waits: new_waitlist}
  end

  defp cleanup_stopping(state = %{runlevel: :stopping}) do
    genserver_pid = self()
    spawn(fn ->
      if state.is_killed do
        Logger.info "stopping ffmpeg server immediately ..."
      else
        Logger.info "stopping ffmpeg server in 30 seconds"
        :timer.sleep(30_000)
      end

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
      send(genserver_pid, :cleanup_complete)
    end)

    state # just return the state; will update later in handle_info()
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
      "-x264opts", "keyint=180:no-scenecut",
      "-pix_fmt" ,"yuv420p",
      "-profile:v", "main",
      "-r", "30",
      "-b:a", prof.bitrate_audio,
      "-c:a", "aac",
      "-preset", "veryfast",
      "-map", "0:v:#{mux.idx_v}",
      "-map", "0:a:#{mux.idx_a}",
    ]

    # TODO: -vf subtitles=<path>:si=<idx>
    ffmpeg_st_args = if (not is_nil(mux.st_path)) and (not is_nil(mux.idx_s)) do
      ["-vf", "subtitles=#{escape_filtergraph(mux.st_path)}:si=#{mux.idx_s}"]
    else
      []
    end

    ffmpeg_hls_args = [
      "-hls_list_size", "10",
      "-hls_time", "6",
      "-hls_flags", "delete_segments",
      "-hls_segment_filename", seg_name,
      seg_path
    ]

    ffmpeg_args = ffmpeg_av_args ++ ffmpeg_st_args ++ ffmpeg_hls_args
  end

  defp escape_filtergraph(fg_arg) do
    fg_arg
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace(":", "\\:")
    |> String.replace("[", "\\[")
    |> String.replace("]", "\\]")
    |> String.replace(",", "\\,")
    |> String.replace(";", "\\;")

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
      |> Enum.map(fn {ty, streams} ->
        reindexed_streams =
          streams
          |> Stream.with_index()
          |> Stream.map(fn {el,idx} -> %{el | idx: idx} end)
          |> Enum.to_list()

        {ty, reindexed_streams}
      end)

    Logger.info "streams :: #{inspect streams}"
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

  defp loop_waiting_for_death(child_pid)
    when is_nil(child_pid), do: :ok

  defp loop_waiting_for_death(child_pid) do
    child_pid = case Lacca.alive?(child_pid) do
      true  -> child_pid
      false -> nil
    end

    :timer.sleep(100)
    loop_waiting_for_death(child_pid)
  end
end
