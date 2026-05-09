defmodule Hardhat.TaskDocs.Server do
  @moduledoc """
  One GenServer per task that holds the authoritative `Yex.Doc` for that
  task's description.

  Responsibilities:
    * On boot, rehydrate the Y.Doc from `task_doc_snapshots` + replay
      `task_doc_updates`.
    * Apply incoming client updates into the in-memory doc and persist them.
    * Periodically compact the log into a fresh snapshot.
    * Hand out the encoded current state to new joiners.

  Awareness (cursors / selections) is not handled here — it's ephemeral and
  goes straight through the channel as broadcast.

  Body_doc materialization (the JSON used for previews / filter search) is
  pushed by clients via a separate channel event, not derived here. When an
  AI agent path lands, it will materialize on its own using `Yex` directly.
  """

  use GenServer

  alias Hardhat.TaskDocs

  @compact_threshold 100

  defmodule State do
    @moduledoc false
    defstruct [
      :task_id,
      :doc,
      :last_seq,
      updates_since_snapshot: 0
    ]
  end

  ## Public API ────────────────────────────────────────────────────────────

  def child_spec(task_id) do
    %{
      id: {__MODULE__, task_id},
      start: {__MODULE__, :start_link, [task_id]},
      restart: :transient
    }
  end

  def start_link(task_id) when is_binary(task_id) do
    GenServer.start_link(__MODULE__, task_id, name: via(task_id))
  end

  @doc """
  Apply a Y.Doc update binary received from a client (or AI agent). The
  caller is responsible for broadcasting the same binary to other channel
  subscribers — the server only owns persistence + in-memory state.
  """
  def apply_update(task_id, update_bin, author_id)
      when is_binary(task_id) and is_binary(update_bin) do
    GenServer.call(via(task_id), {:apply_update, update_bin, author_id})
  end

  @doc """
  Returns `{:ok, state_binary}` containing the entire Y.Doc state encoded as
  a single update — the new joiner applies it once into a fresh local doc.
  """
  def get_state(task_id) when is_binary(task_id) do
    GenServer.call(via(task_id), :get_state)
  end

  defp via(task_id),
    do: {:via, Registry, {Hardhat.TaskDocs.Registry, task_id}}

  ## Callbacks ────────────────────────────────────────────────────────────

  @impl true
  def init(task_id) do
    {snapshot, _state_vector, updates} = TaskDocs.load_state(task_id)
    doc = Yex.Doc.new()

    if is_binary(snapshot) do
      :ok = Yex.apply_update(doc, snapshot)
    end

    Enum.each(updates, fn u -> :ok = Yex.apply_update(doc, u) end)

    {:ok,
     %State{
       task_id: task_id,
       doc: doc,
       last_seq: TaskDocs.max_seq(task_id),
       updates_since_snapshot: length(updates)
     }}
  end

  @impl true
  def handle_call({:apply_update, bin, author_id}, _from, %State{} = state) do
    case Yex.apply_update(state.doc, bin) do
      :ok ->
        {:ok, seq} = TaskDocs.append_update(state.task_id, bin, author_id)

        new_state =
          %{state | last_seq: seq, updates_since_snapshot: state.updates_since_snapshot + 1}
          |> maybe_compact()

        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_state, _from, %State{doc: doc} = state) do
    case Yex.encode_state_as_update(doc) do
      {:ok, bin} -> {:reply, {:ok, bin}, state}
      other -> {:reply, other, state}
    end
  end

  ## Compaction ───────────────────────────────────────────────────────────

  defp maybe_compact(%State{updates_since_snapshot: n} = state)
       when n >= @compact_threshold do
    with {:ok, snapshot} <- Yex.encode_state_as_update(state.doc),
         {:ok, state_vector} <- Yex.encode_state_vector(state.doc),
         {:ok, _} <-
           TaskDocs.save_snapshot(state.task_id, snapshot, state_vector, state.last_seq) do
      %{state | updates_since_snapshot: 0}
    else
      _ -> state
    end
  end

  defp maybe_compact(state), do: state
end
