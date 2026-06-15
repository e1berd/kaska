defmodule Kaska.Repo.Migrations.AddAgentInstructionsAndColumnDescription do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :agent_instructions, :text
    end

    alter table(:columns) do
      add :description, :text
    end
  end
end
