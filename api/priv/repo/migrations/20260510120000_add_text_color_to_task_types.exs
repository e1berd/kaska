defmodule Hardhat.Repo.Migrations.AddTextColorToTaskTypes do
  use Ecto.Migration

  def change do
    alter table(:task_types) do
      add :text_color, :string, null: false, default: "white"
    end
  end
end
