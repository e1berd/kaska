defmodule Kaska.Repo.Migrations.AddAuthorAssigneeTypeToTasks do
  use Ecto.Migration

  def change do
    create table(:task_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :color, :string, null: false, default: "gray"

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create index(:task_types, [:project_id])

    alter table(:tasks) do
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :task_type_id, references(:task_types, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:tasks, [:assignee_id])
    create index(:tasks, [:task_type_id])
  end
end
