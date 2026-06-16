defmodule Kaska.Repo.Migrations.AddDocAndThreadToTaskComments do
  use Ecto.Migration

  def up do
    alter table(:task_comments) do
      add :body_doc, :map
      add :parent_id, references(:task_comments, type: :binary_id, on_delete: :delete_all)
    end

    create index(:task_comments, [:parent_id])

    execute """
    UPDATE task_comments
    SET body_doc = jsonb_build_object(
      'type', 'doc',
      'content', jsonb_build_array(
        jsonb_build_object(
          'type', 'paragraph',
          'content', jsonb_build_array(
            jsonb_build_object('type', 'text', 'text', body)
          )
        )
      )
    )
    WHERE body_doc IS NULL AND body IS NOT NULL AND btrim(body) <> ''
    """

    execute """
    UPDATE task_comments
    SET body_doc = jsonb_build_object('type', 'doc', 'content', jsonb_build_array())
    WHERE body_doc IS NULL
    """
  end

  def down do
    drop index(:task_comments, [:parent_id])

    alter table(:task_comments) do
      remove :parent_id
      remove :body_doc
    end
  end
end
