defmodule Kaska.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :citext, null: false
      add :name, :string, null: false
      add :description, :text

      add :owner_id,
          references(:users, type: :binary_id, on_delete: :restrict),
          null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:projects, [:slug])
    create index(:projects, [:owner_id])

    create table(:columns, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :name, :string, null: false
      add :rank, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:columns, [:project_id, :rank])

    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :column_id,
          references(:columns, type: :binary_id, on_delete: :delete_all),
          null: false

      add :title, :string, null: false
      add :description, :text
      add :rank, :string, null: false

      add :creator_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:column_id, :rank])
    create index(:tasks, [:project_id])
    create index(:tasks, [:creator_id])
  end
end
