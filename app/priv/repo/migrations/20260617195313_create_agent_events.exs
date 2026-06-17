defmodule Kaska.Repo.Migrations.CreateAgentEvents do
  use Ecto.Migration

  def change do
    create table(:agent_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :event_type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all)
      add :comment_id, references(:task_comments, type: :binary_id, on_delete: :delete_all)
      add :agent_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :acked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:agent_events, [:agent_id, :inserted_at])
    create index(:agent_events, [:agent_id, :acked_at])
    create index(:agent_events, [:project_id])
  end
end
