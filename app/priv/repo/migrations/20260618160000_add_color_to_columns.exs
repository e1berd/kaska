defmodule Kaska.Repo.Migrations.AddColorToColumns do
  use Ecto.Migration

  def change do
    alter table(:columns) do
      add :color, :string, null: false, default: "#E8DEF8"
    end
  end
end
