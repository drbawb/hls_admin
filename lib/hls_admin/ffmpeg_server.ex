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
  def start_stream(path) do
    GenServer.call(__MODULE__, {:start, path})
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


  #
  # Callbacks
  #

  def init(_state) do
    config_block = Application.fetch_env!(:hls_admin, HlsAdmin.FfmpegServer)
    Logger.info "Starting FFMPEG server process: #{inspect config_block}"


    {:ok, %{
      runlevel: :stopped,
      root: config_block[:hls_root],
      playlist: config_block[:playlist]
    }}
  end

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  def handle_call(:runlevel, _from, state), do: {:reply, state.runlevel, state}

  def handle_call({:start, path}, _from, state = %{runlevel: :stopped}) do
    {:reply, :ok, state}
  end

  def handle_call({:start, path}, _from, state) do
    {:reply, {:error, :stream_already_started}, state}
  end
    
  def handle_call(:stop, _from, state) do
    {:reply, :ok, %{state | runlevel: :stopped}}
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

  #
  # Implementation
  #

  defp write_playlist(state) do
    pl_path = Path.join(state.root, "#{state.playlist}.m3u8")
    {:ok, file} = File.open(pl_path, [:write])

    # write header
    :ok = IO.write(file, "HLS_ROOT/cdn00.m3u8")
	  :ok = IO.write(file, "#EXTM3U")
    :ok = IO.write(file, "#EXT-X-VERSION:3")

    # level: src
	  :ok = IO.write(file, "#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080")
    :ok = IO.write(file, "cdn00_src/index.m3u8")

    # level: mid
	  :ok = IO.write(file, "#EXT-X-STREAM-INF:BANDWIDTH=2000000,RESOLUTION=1920x1080")
    :ok = IO.write(file, "cdn00_mid/index.m3u8")

    # level: low
	  :ok = IO.write(file, "#EXT-X-STREAM-INF:BANDWIDTH=960000,RESOLUTION=1920x1080")
    :ok = IO.write(file, "cdn00_low/index.m3u8")

    File.close(file)
  end

  defp start_ffmpeg_proc(state, mux, prof) do
    level_name = "#{state.playlist}_#{prof.level_name}"
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
      "-c:a", "libfdk_aac",
      "-preset", "veryfast",
      "-map", "v:#{mux.idx_v}",
      "-map", "a:#{mux.idx_a}",
    ]


    ffmpeg_hls_args = [
      "-hls_list_size", "10",
      "-hls_time", "10",
      "-hls_flags", "delete_segments",
      "-hls_segment_filename", seg_name,
      seg_path
    ]

    ffmpeg_args = ffmpeg_av_args ++ ffmpeg_hls_args
    Logger.info "#{inspect ffmpeg_args}"
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
