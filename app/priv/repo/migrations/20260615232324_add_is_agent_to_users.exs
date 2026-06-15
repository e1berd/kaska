defmodule Kaska.Repo.Migrations.AddIsAgentToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :is_agent, :boolean, null: false, default: false
      add :agent_owner_id, references(:users, type: :binary_id, on_delete: :delete_all)
    end

    create index(:users, [:agent_owner_id])
  end
end
