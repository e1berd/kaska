defmodule Hardhat.Repo do
  use Ecto.Repo,
    otp_app: :hardhat,
    adapter: Ecto.Adapters.Postgres
end
