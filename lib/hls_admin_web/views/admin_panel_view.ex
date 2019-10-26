defmodule HlsAdminWeb.AdminView do
  use Phoenix.LiveView

  alias HlsAdmin.StreamForm
  alias HlsAdminWeb.PageView
  require Logger

  def handle_info(:poll_ffmpeg, socket) do
    # Process.send_after(self(), :poll_ffmpeg, 1000)
    status = HlsAdmin.FfmpegServer.status()
    socket =
      socket
      |> assign(:ffmpeg_status, status)

    {:noreply, socket}
  end


  defp fetch(socket) do
    ui_pid = socket.assigns.ui_pid
    {:ok, ents} = GenServer.call(ui_pid, :enumerate)
    {:ok, cwd}  = GenServer.call(ui_pid, :cwd)

    # group dirents by type
    ents = ents |> Enum.group_by(
      fn {ty, _}  -> ty end,
      fn {_, val} -> val end
    )

    # reload ffmpeg status optimistically 
    status = HlsAdmin.FfmpegServer.status()

    # push new states to client
    socket
    |> assign(:cwd, cwd)
    |> assign(:dirs, ents[:dir] || [])
    |> assign(:files, ents[:file] || [])
    |> assign(:ffmpeg_status, status)
    |> load_streams()
  end

  defp load_streams(socket) do
    # first load all streams from the video (if avail)
    socket = case socket.assigns.current_video do
      nil  -> socket
      path ->
        {:ok, probe_resp} = HlsAdmin.FfmpegServer.probe_stream(path)
        Logger.debug "video resp: #{inspect probe_resp}"

        socket
        |> assign(:opts_video, probe_resp[:video] || [])
        |> assign(:opts_audio, probe_resp[:audio] || [])
    end

    # next load *just* subtitle streams
    socket = case socket.assigns.current_subs do
      nil -> socket
      path ->
        {:ok, probe_resp} = HlsAdmin.FfmpegServer.probe_stream(path)
        Logger.debug "subs resp: #{inspect probe_resp}"

        socket
        |> assign(:opts_subs, probe_resp[:subtitle] || [])
    end
  end

  def mount(_session, socket) do
    {:ok, ui_pid} = GenServer.start_link(HlsAdmin.AdminUI, [])
    status = HlsAdmin.FfmpegServer.status()
    changeset = StreamForm.changeset(%StreamForm{})

    Phoenix.PubSub.subscribe HlsAdmin.PubSub, "ffmpeg:status_change"

    socket = 
      socket
      |> assign(:changeset, changeset)
      |> assign(:show_debug, false)
      |> assign(:show_picker, false)
      |> assign(:current_video, nil)
      |> assign(:current_subs, nil)
      |> assign(:opts_video, [])
      |> assign(:opts_audio, [])
      |> assign(:opts_subs, [])
      |> assign(:ui_pid, ui_pid)
      |> assign(:ffmpeg_status, status)
      |> fetch()

    # update ffmpeg status every second
    send(self(), :poll_ffmpeg)

    {:ok, socket}
  end

  def render(assigns) do
    PageView.render("admin.html", assigns)
  end

  # hide file picker and clear mode
  def handle_event("choose_close", params, socket) do
    socket =
      socket
      |> assign(:picker_mode, nil)
      |> assign(:show_picker, false)

    {:noreply, fetch(socket)}
  end

  # show file picker in video mode
  def handle_event("choose_video", _params, socket) do
    socket = 
      socket
      |> assign(:picker_mode, "video")
      |> assign(:show_picker, true)

    {:noreply, fetch(socket)}
  end

  # show file picker in subtitle mode
  def handle_event("choose_subtitles", _params, socket) do
    socket = 
      socket
      |> assign(:picker_mode, "subtitles")
      |> assign(:show_picker, true)

    {:noreply, fetch(socket)}
  end

  def handle_event("clear_subtitles", _params, socket) do

    changeset =
        socket.assigns.changeset
        |> Map.put(:errors, [])
        |> StreamForm.changeset(%{st_path: nil})
        |> Map.put(:action, :insert)

    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:current_subs, nil)

    {:noreply, fetch(socket)}
  end

  def handle_event("push", %{"path" => path}, socket) do
    # push path onto stack
    Logger.info "got add event: #{inspect path}"
    ui_pid = socket.assigns.ui_pid
    :ok = GenServer.call(ui_pid, {:push, path})

    # update view
    {:noreply, fetch(socket)}
  end

  def handle_event("pop", _params, socket) do
    Logger.info "got pop event"
    ui_pid = socket.assigns.ui_pid
    :ok = GenServer.call(ui_pid, :pop)
    {:noreply, fetch(socket)}
  end

  def handle_event("choose", %{"path" => path}, socket) do
    ui_pid = socket.assigns.ui_pid
    {:ok, cwd} = GenServer.call(ui_pid, :cwd)
    full_path = Path.join(cwd, path)
    Logger.debug "selected file: #{inspect full_path}"
    Logger.debug "selected mode: #{inspect socket.assigns.picker_mode}"

    # what was this file browser opened to select?
    current_sym = case socket.assigns.picker_mode do
      "video" -> :current_video
      "subtitles" -> :current_subs
    end

    # TODO: update changeset. (this should really be all we have to do, get 
    # rid of above block which duplicates this ...
    changeset = case socket.assigns.picker_mode do
      "video" ->
        socket.assigns.changeset
        |> Map.put(:errors, [])
        |> StreamForm.changeset(%{av_path: full_path})
        |> Map.put(:action, :insert)
        

      "subtitles" ->
        socket.assigns.changeset
        |> Map.put(:errors, [])
        |> StreamForm.changeset(%{st_path: full_path})
        |> Map.put(:action, :insert)
    end

    # assign the stuff
    socket =
      socket
      |> assign(:changeset, changeset)
      |> assign(:picker_mode, nil)
      |> assign(:show_picker, false)
      |> assign(current_sym, full_path)

    {:noreply, fetch(socket)}
  end

  def handle_event("validate", params, socket) do
    Logger.debug "validate :: #{inspect(params)}"

    changeset =
      StreamForm.changeset(%StreamForm{}, params["stream_form"])
      |> Map.put(:action, :insert)

    socket = assign(socket, :changeset, changeset)
    {:noreply, fetch(socket)}
  end

  def handle_event("save", params, socket) do
    Logger.debug "save :: #{inspect(params)}"

    case socket.assigns.ffmpeg_status do
      %{runlevel: :running} -> _stop_stream(socket, params)
      %{runlevel: :stopped} -> _start_stream(socket, params)
      %{runlevel: runlevel} ->
        Logger.warn "User clicked submit in unkown state: #{inspect runlevel}"
        {:noreply, fetch(socket)}
    end

  end

  defp _start_stream(socket, %{"stream_form" => stream_form}) do
    Logger.info "starting stream"

    changeset =
      StreamForm.changeset(%StreamForm{}, stream_form)
      |> Ecto.Changeset.apply_action(:insert)

    case changeset do
      {:ok, stream_form} ->
        HlsAdmin.FfmpegServer.start_stream(stream_form)
        {:noreply, fetch(socket)}

      {:error, changes} ->
        socket =
          socket
          |> assign(:changeset, changes)
          |> fetch()

        {:noreply, socket}
    end
  end

  defp _stop_stream(socket, params) do
    Logger.info "stopping stream"
    HlsAdmin.FfmpegServer.stop_stream()
    {:noreply, fetch(socket)}
  end

  def handle_event("show_debug", params, socket) do
    {:noreply, assign(socket, :show_debug, not socket.assigns.show_debug)}
  end

  def handle_info({:ffmpeg, status}, socket) do
    Logger.info "status update: #{status}"
    {:noreply, fetch(socket)}
  end
end
