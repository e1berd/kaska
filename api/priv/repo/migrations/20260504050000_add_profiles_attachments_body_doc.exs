defmodule Kaska.Repo.Migrations.AddProfilesAttachmentsBodyDoc do
  use Ecto.Migration

  def up do
    # ── Profile fields ─────────────────────────────────────────────
    alter table(:users) do
      add :display_name, :string
      add :avatar_key, :string
    end

    # ── tasks: text description → jsonb body_doc ──────────────────
    alter table(:tasks) do
      add :body_doc, :jsonb
    end

    flush()

    # Wrap any existing plain-text description into a tiptap-shaped doc:
    #   { "type": "doc", "content": [ { "type": "paragraph",
    #     "content": [ { "type": "text", "text": "<old>" } ] } ] }
    execute("""
    UPDATE tasks
    SET body_doc = jsonb_build_object(
      'type', 'doc',
      'content', jsonb_build_array(
        jsonb_build_object(
          'type', 'paragraph',
          'content', jsonb_build_array(
            jsonb_build_object('type', 'text', 'text', description)
          )
        )
      )
    )
    WHERE description IS NOT NULL AND length(trim(description)) > 0
    """)

    execute("""
    UPDATE tasks
    SET body_doc = jsonb_build_object('type','doc','content', jsonb_build_array())
    WHERE body_doc IS NULL
    """)

    alter table(:tasks) do
      modify :body_doc, :jsonb, null: false
      remove :description
    end

    # ── Attachments ────────────────────────────────────────────────
    create table(:attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # Polymorphic-by-convention: an attachment belongs to one parent,
      # identified by (parent_type, parent_id). Right now: "task" | "user".
      add :parent_type, :string, null: false
      add :parent_id, :binary_id, null: false

      add :kind, :string, null: false
      add :filename, :string, null: false
      add :mime, :string, null: false
      add :size, :bigint, null: false
      add :storage_key, :string, null: false
      add :status, :string, null: false, default: "pending"

      add :creator_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:attachments, [:parent_type, :parent_id])
    create unique_index(:attachments, [:storage_key])
  end

  def down do
    drop table(:attachments)

    alter table(:tasks) do
      add :description, :text
    end

    flush()

    execute("""
    UPDATE tasks
    SET description = (
      SELECT string_agg(text_node.text, E'\n\n')
      FROM jsonb_array_elements(body_doc->'content') paragraph,
           jsonb_array_elements(paragraph->'content') text_node
      WHERE text_node->>'type' = 'text'
    )
    """)

    alter table(:tasks) do
      remove :body_doc
    end

    alter table(:users) do
      remove :avatar_key
      remove :display_name
    end
  end
end
