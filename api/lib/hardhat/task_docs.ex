defmodule Hardhat.TaskDocs do
  @moduledoc """
  Persistence for collaborative Y.Doc state of task descriptions.

  Two tables back this:
  - `task_doc_snapshots`: a single merged Y.Doc snapshot per task, plus its
    state vector. Replaced in place when the doc is compacted.
  - `task_doc_updates`: append-only log of Y.Doc updates received between
    snapshots. Pruned when a fresh snapshot covers them.

  A late-joining client receives `snapshot ++ updates_after(snapshot.seq)`,
  which it applies into its local Y.Doc. The CRDT (`Yex`) takes care of
  ordering — `seq` here is just a watermark for prune/load, not a logical
  clock.
  """

  import Ecto.Query

  alias Hardhat.Repo
  alias Hardhat.Projects.{Task, TaskDocSnapshot, TaskDocUpdate}

  @doc """
  Returns `{snapshot_binary | nil, state_vector_binary | nil, [update_binary]}`
  for the given task. Used on channel join to rehydrate a client.
  """
  def load_state(task_id) do
    snapshot = Repo.get(TaskDocSnapshot, task_id)
    seq = if snapshot, do: snapshot.seq, else: 0

    updates =
      from(u in TaskDocUpdate,
        where: u.task_id == ^task_id and u.seq > ^seq,
        order_by: [asc: u.seq],
        select: u.update
      )
      |> Repo.all()

    {snapshot && snapshot.snapshot, snapshot && snapshot.state_vector, updates}
  end

  @doc """
  Returns the highest `seq` ever assigned to this task's update log, or `0`
  if the task has no updates yet. Used at server boot to seed the watermark.
  """
  def max_seq(task_id) when is_binary(task_id) do
    Repo.one(
      from u in TaskDocUpdate,
        where: u.task_id == ^task_id,
        select: max(u.seq)
    ) || 0
  end

  @doc """
  Appends a Y.Doc update binary to the task's log. Returns the assigned `seq`.
  """
  def append_update(task_id, update_bin, author_id)
      when is_binary(task_id) and is_binary(update_bin) do
    {1, [%{seq: seq}]} =
      Repo.insert_all(
        TaskDocUpdate,
        [
          %{
            task_id: task_id,
            update: update_bin,
            author_id: author_id,
            inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)
          }
        ],
        returning: [:seq]
      )

    {:ok, seq}
  end

  @doc """
  Replaces the snapshot for a task and prunes any updates whose `seq` is at
  or below `seq`. Run inside a transaction to keep load_state consistent.
  """
  def save_snapshot(task_id, snapshot_bin, state_vector_bin, seq)
      when is_binary(task_id) and is_binary(snapshot_bin) and is_binary(state_vector_bin) and
             is_integer(seq) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      Repo.insert_all(
        TaskDocSnapshot,
        [
          %{
            task_id: task_id,
            snapshot: snapshot_bin,
            state_vector: state_vector_bin,
            seq: seq,
            updated_at: now
          }
        ],
        on_conflict: {:replace, [:snapshot, :state_vector, :seq, :updated_at]},
        conflict_target: :task_id
      )

      from(u in TaskDocUpdate,
        where: u.task_id == ^task_id and u.seq <= ^seq
      )
      |> Repo.delete_all()

      :ok
    end)
  end

  @doc """
  Updates `tasks.body_doc` directly without going through the changeset.
  Server-side materialization from the Y.Doc — bypasses validation since
  the doc is produced by the server itself.
  """
  def update_body_doc(task_id, %{"type" => "doc"} = doc) when is_binary(task_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {n, _} =
      from(t in Task, where: t.id == ^task_id)
      |> Repo.update_all(set: [body_doc: doc, updated_at: now])

    if n == 1, do: :ok, else: {:error, :not_found}
  end
end
