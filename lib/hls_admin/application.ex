defmodule HlsAdmin.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Start the Ecto repository
      # HlsAdmin.Repo,
      # Start the PubSub server
      {Phoenix.PubSub, [name: HlsAdmin.PubSub, adapter: Phoenix.PubSub.PG2]},
      # Start the endpoint when the application starts
      HlsAdminWeb.Endpoint,
      # Start the FFMPEG Manager Process
      {HlsAdmin.FfmpegServer, Application.fetch_env!(:hls_admin, HlsAdmin.FfmpegServer)},
      # Starts a worker by calling: HlsAdmin.Worker.start_link(arg)
      # {HlsAdmin.Worker, arg},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HlsAdmin.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    HlsAdminWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
