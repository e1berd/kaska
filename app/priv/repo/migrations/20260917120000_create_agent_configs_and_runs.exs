defmodule Kaska.Repo.Migrations.CreateAgentConfigsAndRuns do
  use Ecto.Migration

  def change do
    create table(:agent_configs, primary_key: false) do
      add :agent_id, references(:users, type: :binary_id, on_delete: :delete_all),
        primary_key: true

      add :kind, :string, null: false, default: "chat_only"
      add :provider_kind, :string
      add :provider_preset, :string
      add :base_url, :string
      add :model, :string
      add :encrypted_api_key, :binary
      add :system_prompt, :text
      add :auto_run_enabled, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create table(:agent_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :agent_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, type: :binary_id, on_delete: :nilify_all)

      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all),
        null: false

      add :requested_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :trigger, :string, null: false, default: "manual"
      add :status, :string, null: false, default: "pending"
      add :container_id, :string
      add :api_token_id, references(:api_tokens, type: :binary_id, on_delete: :nilify_all)
      add :started_at, :utc_datetime
      add :finished_at, :utc_datetime
      add :exit_code, :integer
      add :exit_reason, :text
      add :log_tail, :text, null: false, default: ""
      add :log_object_key, :string

      timestamps(type: :utc_datetime)
    end

    create index(:agent_runs, [:agent_id, :inserted_at])
    create index(:agent_runs, [:task_id, :inserted_at])
    create index(:agent_runs, [:project_id])

    create unique_index(:agent_runs, [:task_id],
             where: "status IN ('pending', 'running')",
             name: :agent_runs_one_active_per_task
           )
  end
end
