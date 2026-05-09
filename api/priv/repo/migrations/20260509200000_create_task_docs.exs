defmodule Hardhat.Repo.Migrations.CreateTaskDocs do
  use Ecto.Migration

  def change do
    # Snapshot of a Y.Doc for a task: the merged binary state and a state
    # vector for diff calculations on join. One row per task; replaced in
    # place when the doc is compacted.
    create table(:task_doc_snapshots, primary_key: false) do
      add :task_id,
          references(:tasks, type: :binary_id, on_delete: :delete_all),
          primary_key: true,
          null: false

      add :snapshot, :bytea, null: false
      add :state_vector, :bytea, null: false
      add :seq, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime, inserted_at: false, updated_at: :updated_at)
    end

    # Append-only log of Y.Doc updates received from clients between
    # snapshots. New clients receive the snapshot + all updates with
    # `seq > snapshot.seq`. Compaction prunes everything covered by the
    # latest snapshot.
    create table(:task_doc_updates, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :task_id,
          references(:tasks, type: :binary_id, on_delete: :delete_all),
          null: false

      add :seq, :bigserial, null: false
      add :update, :bytea, null: false
      add :author_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:task_doc_updates, [:task_id, :seq])
  end
end
