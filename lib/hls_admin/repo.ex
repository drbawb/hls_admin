defmodule HlsAdmin.Repo do
  use Ecto.Repo,
    otp_app: :hls_admin,
    adapter: Ecto.Adapters.Postgres
end
