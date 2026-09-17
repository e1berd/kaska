defmodule Kaska.Repo.Migrations.AddAuthMethodToAgentConfigs do
  use Ecto.Migration

  def change do
    alter table(:agent_configs) do
      add :auth_method, :string, null: false, default: "api_key"
    end
  end
end
