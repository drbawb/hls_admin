defmodule HlsAdminWeb.AdminView do
  use Phoenix.LiveView

  alias HlsAdminWeb.PageView
  require Logger

  defp fetch(socket) do
    ui_pid = socket.assigns.ui_pid

    {:ok, dirs} = GenServer.call(ui_pid, :enumerate)
    {:ok, cwd}  = GenServer.call(ui_pid, :cwd)

    socket = socket
             |> assign(:cwd, cwd)
             |> assign(:dirs, dirs)
  end

  def mount(_session, socket) do
    {:ok, ui_pid} = GenServer.start_link(HlsAdmin.AdminUI, [])
    {:ok, dirs} = GenServer.call(ui_pid, :enumerate)

    socket = socket
             |> assign(:ui_pid, ui_pid)
             |> fetch()

    {:ok, socket}
  end

  def render(assigns) do
    PageView.render("admin.html", assigns)
  end

  def handle_event("add", %{"path" => path}, socket) do
    # push path onto stack
    Logger.info "got add event: #{inspect path}"
    ui_pid = socket.assigns.ui_pid
    :ok = GenServer.call(ui_pid, {:push, path["dir"]})

    # update view
    {:noreply, fetch(socket)}
  end

  def terminate(reason, socket) do
    Logger.debug "oh bye..."
  end
end
