defmodule Hardhat.Repo.Migrations.AddDescriptionToTaskTypes do
  use Ecto.Migration

  def change do
    alter table(:task_types) do
      add :description, :text
    end
  end
end

