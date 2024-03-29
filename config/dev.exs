import Config

# Configure your database
config :hls_admin, HlsAdmin.Repo,
  username: "postgres",
  password: "postgres",
  database: "hls_admin_dev",
  hostname: "localhost",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we use it
# with webpack to recompile .js and .css sources.
config :hls_admin, HlsAdminWeb.Endpoint,
  http: [port: 4000],
  debug_errors: true,
  code_reloader: true,
  check_origin: false,
  watchers: [
    # Start the esbuild watcher by calling Esbuild.install_and_run(:default, args)
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
  ]

# This is a list of logins which will be available in the development environment.
#
# Please use `mix hls.hash <password>` to hash your password & associate it with a
# login here.
#
# You can use the `config/prod.secret.exs` file to configure this key in your
# production environment by e.g: reading a file, database, environment variable, etc. 
#
config :hls_admin, :logins, %{
  "admin" => "$argon2id$v=19$m=131072,t=8,p=4$e1l3jrod0geWlTIcyvaU0g$7c6qe0N3Z82ekGhakQCxrsvW7yzRCPodmoWIdCMvCC0"
}

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Note that this task requires Erlang/OTP 20 or later.
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :hls_admin, HlsAdminWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/hls_admin_web/{live,views}/.*(ex)$",
      ~r"lib/hls_admin_web/templates/.*(eex)$"
    ]
  ]

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime
