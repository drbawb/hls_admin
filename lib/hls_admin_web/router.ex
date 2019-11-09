defmodule HlsAdminWeb.Router do
  use HlsAdminWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug Phoenix.LiveView.Flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
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
