# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :hls_admin,
  ecto_repos: [HlsAdmin.Repo]

# Configure FFMPEG Server Process
config :hls_admin, HlsAdmin.FfmpegServer,
  hls_root: "/srv/hls",
  playlist: "cdn00"

# Configure server file browser process
config :hls_admin, HlsAdmin.AdminUI,
  parent_path: "/mnt/media"

# Configures the endpoint
config :hls_admin, HlsAdminWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "EdsTOPn9NSywmF3rN1hVoXmPiNQG1EphLai47sLmEAXaa5Rd8KbJNrdAfHfRD3xT",
  render_errors: [view: HlsAdminWeb.ErrorView, accepts: ~w(html json)],
  pubsub_server: HlsAdmin.PubSub,
  live_view: [signing_salt: "cq6As+iTY6BQ6GLaeombnvdNq7rZ6cwH"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
