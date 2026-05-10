defmodule Kaska.Repo do
  use Ecto.Repo,
    otp_app: :kaska,
    adapter: Ecto.Adapters.Postgres
end
