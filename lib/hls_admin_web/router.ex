defmodule HlsAdminWeb.Router do
  use HlsAdminWeb, :router
  import Phoenix.LiveDashboard.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_root_layout, {HlsAdminWeb.LayoutView, :root}
  end

  pipeline :admin do 
    plug :require_admin_auth
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HlsAdminWeb do
    pipe_through :browser

    # admin authorization controller
    get  "/",       AuthController, :index
    get  "/login",  AuthController, :new
    get  "/logout", AuthController, :delete
    post "/create", AuthController, :create
  end

  scope "/admin", HlsAdminWeb do
    pipe_through :browser
    pipe_through :admin

    live_dashboard "/dashboard"
  end

  defp require_admin_auth(conn, _opts) do
    case get_session(conn, :auth_role) do
      :admin -> conn # continue
      _role  -> conn |> Phoenix.Controller.redirect(to: "/")
    end
  end
end
