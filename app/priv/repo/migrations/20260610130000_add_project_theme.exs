defmodule Kaska.Repo.Migrations.AddProjectTheme do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :theme_slug, :string
    end

    create table(:project_theme_prefs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :theme_slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_theme_prefs, [:project_id, :user_id])
  end
end
