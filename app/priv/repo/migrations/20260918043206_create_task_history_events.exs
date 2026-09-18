defmodule Kaska.Repo.Migrations.CreateTaskHistoryEvents do
  use Ecto.Migration

  def change do
    create table(:task_history_events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :task_id,
          references(:tasks, type: :binary_id, on_delete: :delete_all),
          null: false

      add :actor_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :batch_id, :binary_id, null: false
      add :kind, :string, null: false
      add :field, :string
      add :old_value, :map
      add :new_value, :map
      add :comment, :text
      add :regression, :boolean, default: false, null: false

      add :reverts_event_id,
          references(:task_history_events, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:task_history_events, [:task_id, :inserted_at])
    create index(:task_history_events, [:project_id, :inserted_at])
    create index(:task_history_events, [:batch_id])
    create index(:task_history_events, [:reverts_event_id])
  end
end
