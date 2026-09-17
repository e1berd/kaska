defmodule Kaska.Repo.Migrations.RetireClerkTokensAndAgentEvents do
  use Ecto.Migration

  def up do
    execute """
    UPDATE api_tokens
    SET revoked_at = now(), updated_at = now()
    WHERE revoked_at IS NULL AND name NOT LIKE 'run:%'
    """

    drop_if_exists table(:agent_events)

    alter table(:agent_configs) do
      remove :kind
    end
  end

  def down do
    alter table(:agent_configs) do
      add :kind, :string, null: false, default: "code_capable"
    end

    create table(:agent_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_type, :string, null: false, default: "comment_reply"
      add :payload, :map, null: false, default: %{}
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all)
      add :comment_id, references(:task_comments, type: :binary_id, on_delete: :delete_all)
      add :acked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:agent_events, [:agent_id, :inserted_at])
    create index(:agent_events, [:agent_id, :acked_at])
    create index(:agent_events, [:project_id])
  end
end
