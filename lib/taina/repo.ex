defmodule Taina.Repo do
  use Ecto.Repo,
    otp_app: :taina,
    adapter: Ecto.Adapters.Postgres
end
