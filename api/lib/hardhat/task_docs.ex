defmodule Hardhat.TaskDocs do
  @moduledoc false

  import Ecto.Query

  alias Hardhat.Repo
  alias Hardhat.Projects.{Task, TaskDocSnapshot, TaskDocUpdate}

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

  def max_seq(task_id) when is_binary(task_id) do
    Repo.one(
      from u in TaskDocUpdate,
        where: u.task_id == ^task_id,
        select: max(u.seq)
    ) || 0
  end

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

  def update_body_doc(task_id, %{"type" => "doc"} = doc) when is_binary(task_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {n, _} =
      from(t in Task, where: t.id == ^task_id)
      |> Repo.update_all(set: [body_doc: doc, updated_at: now])

    if n == 1, do: :ok, else: {:error, :not_found}
  end
end
