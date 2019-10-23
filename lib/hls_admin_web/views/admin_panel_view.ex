defmodule HlsAdminWeb.AdminView do
  use Phoenix.LiveView

  alias HlsAdminWeb.PageView
  require Logger

  defp fetch(socket) do
    ui_pid = socket.assigns.ui_pid
    {:ok, ents} = GenServer.call(ui_pid, :enumerate)
    {:ok, cwd}  = GenServer.call(ui_pid, :cwd)

    # group files and dirs together
    Logger.debug inspect(ents)

    ents = ents |> Enum.group_by(
      fn {ty, _}  -> ty end,
      fn {_, val} -> val end
    )

    socket
    |> assign(:cwd, cwd)
    |> assign(:dirs, ents[:dir] || [])
    |> assign(:files, ents[:file] || [])
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
        |> assign(:opts_subs,  probe_resp[:subtitle] || [])
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

    socket = 
      socket
      |> assign(:show_picker, false)
      |> assign(:current_video, nil)
      |> assign(:current_subs, nil)
      |> assign(:opts_video, [])
      |> assign(:opts_audio, [])
      |> assign(:opts_subs, [])
      |> assign(:ui_pid, ui_pid)
      |> fetch()

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

    current_sym = case socket.assigns.picker_mode do
      "video" -> :current_video
      "subtitles" -> :current_subs
    end

    socket =
      socket
      |> assign(:picker_mode, nil)
      |> assign(:show_picker, false)
      |> assign(current_sym, full_path)

    {:noreply, fetch(socket)}
  end

  def handle_event("stream_validate", params, socket) do
    Logger.debug inspect(params)
    {:noreply, fetch(socket)}
  end

  def handle_event("stream_save", params, socket) do
    Logger.debug inspect(params)
    {:noreply, fetch(socket)}
  end
end
