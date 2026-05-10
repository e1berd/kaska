defmodule Kaska.Repo.Migrations.AddProjectAvatarAndBackground do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :avatar_key, :string
      add :background_key, :string
    end
  end
end
