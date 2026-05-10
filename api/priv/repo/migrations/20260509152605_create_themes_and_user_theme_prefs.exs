defmodule Kaska.Repo.Migrations.CreateThemesAndUserThemePrefs do
  use Ecto.Migration

  def change do
    create table(:themes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :citext, null: false
      add :name, :string, null: false
      add :palette_light, :map, null: false
      add :palette_dark, :map, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:themes, [:slug])

    alter table(:users) do
      add :theme_slug, :string
      add :theme_mode, :string
    end
  end
end
