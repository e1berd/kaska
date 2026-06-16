defmodule Kaska.Repo.Migrations.CreateAgentEvents do
  use Ecto.Migration

  def change do
    create table(:agent_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :seq, :bigserial, null: false
      add :agent_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :type, :string, null: false
      add :payload, :map, null: false, default: %{}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:agent_events, [:agent_id, :seq])

    create table(:agent_event_cursors, primary_key: false) do
      add :agent_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :acked_seq, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime)
    end
  end
end
