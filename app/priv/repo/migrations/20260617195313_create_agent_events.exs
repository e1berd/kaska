defmodule Kaska.Repo.Migrations.CreateAgentEvents do
  use Ecto.Migration

  def up do
    alter table(:agent_events) do
      add :event_type, :string, null: false, default: "comment_reply"
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all)
      add :comment_id, references(:task_comments, type: :binary_id, on_delete: :delete_all)
      add :acked_at, :utc_datetime
      add :updated_at, :utc_datetime
      remove :seq
      remove :type
    end

    drop table(:agent_event_cursors)

    drop index(:agent_events, [:agent_id, :seq])

    create index(:agent_events, [:agent_id, :inserted_at])
    create index(:agent_events, [:agent_id, :acked_at])
    create index(:agent_events, [:project_id])
  end

  def down do
    drop index(:agent_events, [:project_id])
    drop index(:agent_events, [:agent_id, :acked_at])
    drop index(:agent_events, [:agent_id, :inserted_at])

    create index(:agent_events, [:agent_id, :seq])

    create table(:agent_event_cursors, primary_key: false) do
      add :agent_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :acked_seq, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    alter table(:agent_events) do
      add :seq, :bigserial, null: false
      add :type, :string, null: false
      remove :event_type
      remove :task_id
      remove :comment_id
      remove :acked_at
      remove :updated_at
    end
  end
end
