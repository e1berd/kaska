defmodule Kaska.Repo.Migrations.CreateTaskComments do
  use Ecto.Migration

  def change do
    create table(:task_comments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :guest_name, :string
      add :task_id, references(:tasks, type: :binary_id, on_delete: :delete_all), null: false
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:task_comments, [:task_id, :inserted_at])
    create index(:task_comments, [:project_id, :inserted_at])
    create index(:task_comments, [:author_id])
  end
end
