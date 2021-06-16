defmodule HlsAdminWeb.Router do
  use HlsAdminWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_root_layout, {HlsAdminWeb.LayoutView, :root}
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

  # Other scopes may use custom stacks.
  # scope "/api", HlsAdminWeb do
  #   pipe_through :api
  # end
end
