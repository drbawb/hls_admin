defmodule HlsAdminWeb.PageController do
  use HlsAdminWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
