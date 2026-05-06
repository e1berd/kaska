defmodule Hardhat.Repo.Migrations.AddDatesToTasks do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :start_date, :utc_datetime
      add :end_date, :utc_datetime
    end
  end
end
