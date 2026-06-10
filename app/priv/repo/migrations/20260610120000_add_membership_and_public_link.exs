defmodule Kaska.Repo.Migrations.AddMembershipAndPublicLink do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :public_link, :boolean, null: false, default: false
    end

    create table(:project_members, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false, default: "member"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_members, [:project_id, :user_id])
    create index(:project_members, [:user_id])

    create table(:project_invites, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :project_id,
          references(:projects, type: :binary_id, on_delete: :delete_all),
          null: false

      add :token, :string, null: false
      add :email, :string

      add :invited_by_id,
          references(:users, type: :binary_id, on_delete: :nilify_all)

      add :expires_at, :utc_datetime
      add :accepted_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:project_invites, [:token])
    create index(:project_invites, [:project_id])

    execute(
      """
      INSERT INTO project_members (id, project_id, user_id, role, inserted_at, updated_at)
      SELECT gen_random_uuid(), p.id, p.owner_id, 'owner', NOW(), NOW()
      FROM projects p
      """,
      "DELETE FROM project_members WHERE role = 'owner'"
    )
  end
end
