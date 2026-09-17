defmodule Kaska.Repo.Migrations.CreateTaskAssignees do
  use Ecto.Migration

  def up do
    create table(:task_assignees, primary_key: false) do
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :inserted_at, :utc_datetime, null: false, default: fragment("now()")
    end

    create index(:task_assignees, [:user_id])

    execute """
    INSERT INTO task_assignees (task_id, user_id)
    SELECT id, assignee_id FROM tasks WHERE assignee_id IS NOT NULL
    """

    alter table(:tasks) do
      remove :assignee_id
      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end
  end

  def down do
    alter table(:tasks) do
      add :assignee_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      remove :updated_by_id
    end

    create index(:tasks, [:assignee_id])

    execute """
    UPDATE tasks SET assignee_id = first_assignee.user_id
    FROM (
      SELECT DISTINCT ON (task_id) task_id, user_id
      FROM task_assignees
      ORDER BY task_id, inserted_at
    ) AS first_assignee
    WHERE tasks.id = first_assignee.task_id
    """

    drop table(:task_assignees)
  end
end
