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
  end

  def mount(_session, socket) do
    {:ok, ui_pid} = GenServer.start_link(HlsAdmin.AdminUI, [])

    socket = 
      socket
      |> assign(:show_picker, false)
      |> assign(:current_video, nil)
      |> assign(:current_subs, nil)
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
  def handle_event("choose_video", params, socket) do
    socket = 
      socket
      |> assign(:picker_mode, "video")
      |> assign(:show_picker, true)

    {:noreply, fetch(socket)}
  end

  # show file picker in subtitle mode
  def handle_event("choose_subtitles", params, socket) do
    socket = 
      socket
      |> assign(:picker_mode, "subtitles")
      |> assign(:show_picker, true)

    {:noreply, fetch(socket)}
  end

  def handle_event("add", %{"path" => path}, socket) do
    # push path onto stack
    Logger.info "got add event: #{inspect path}"
    ui_pid = socket.assigns.ui_pid
    :ok = GenServer.call(ui_pid, {:push, path})

    # update view
    {:noreply, fetch(socket)}
  end

  def handle_event("select", %{"path" => path}, socket) do
    Logger.info "selected file: #{inspect path}"
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
