defmodule HlsAdmin.FfmpegServer do
  use GenServer

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


  #
  # Callbacks
  #

  def init(_state) do
    {:ok, %{}}
  end

end
