defmodule Hardhat.Repo.Migrations.AddSettingsTable do
  use Ecto.Migration

  def change do
    create table(:settings, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:settings, [:key])

    create table(:invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :email, :string
      add :expires_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invites, [:token])
  end
end
