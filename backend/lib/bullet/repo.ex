defmodule Bullet.Repo do
  use Ecto.Repo,
    otp_app: :bullet,
    adapter: Ecto.Adapters.Postgres
end
