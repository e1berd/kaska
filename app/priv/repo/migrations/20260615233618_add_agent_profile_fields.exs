defmodule Kaska.Repo.Migrations.AddAgentProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :agent_description, :text
      add :agent_role, :string
    end
  end
end
