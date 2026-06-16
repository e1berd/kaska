defmodule Kaska.AgentEvents do
  @moduledoc """
  Durable per-agent event outbox with at-least-once delivery.

  Each event is persisted with a monotonic `seq`. An agent consumes its stream
  by reading events with `seq` greater than its acknowledged cursor; the cursor
  only advances on an explicit ack, so an event keeps being redelivered until
  the agent confirms it. A `Phoenix.PubSub` broadcast lets a parked long-poll
  wake up the instant a new event lands.
  """

  import Ecto.Query

  alias Kaska.Repo
  alias Kaska.AgentEvents.{AgentEvent, EventCursor}

  @pubsub Kaska.PubSub

  def topic(agent_id) when is_binary(agent_id), do: "agent_events:" <> agent_id

  def subscribe(agent_id) when is_binary(agent_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(agent_id))
  end

  def unsubscribe(agent_id) when is_binary(agent_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(agent_id))
  end

  @doc "Persists one event for `agent_id` and notifies any parked listener."
  def record(agent_id, project_id, type, payload \\ %{}) do
    %AgentEvent{}
    |> AgentEvent.changeset(%{
      agent_id: agent_id,
      project_id: project_id,
      type: type,
      payload: payload
    })
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        Phoenix.PubSub.broadcast(@pubsub, topic(agent_id), {:agent_event, event.seq})
        {:ok, event}

      other ->
        other
    end
  end

  @doc "Records the same event for several agents. Returns the number stored."
  def record_many(agent_ids, project_id, type, payload \\ %{}) when is_list(agent_ids) do
    agent_ids
    |> Enum.uniq()
    |> Enum.reduce(0, fn agent_id, acc ->
      case record(agent_id, project_id, type, payload) do
        {:ok, _} -> acc + 1
        _ -> acc
      end
    end)
  end

  @doc "Acknowledged cursor for `agent_id` (0 when the agent has none yet)."
  def cursor(agent_id) when is_binary(agent_id) do
    Repo.one(from c in EventCursor, where: c.agent_id == ^agent_id, select: c.acked_seq) || 0
  end

  @doc "Unacknowledged events for `agent_id` with `seq` greater than `after_seq`."
  def pending(agent_id, after_seq, limit \\ 100)
      when is_binary(agent_id) and is_integer(after_seq) do
    Repo.all(
      from e in AgentEvent,
        where: e.agent_id == ^agent_id and e.seq > ^after_seq,
        order_by: [asc: e.seq],
        limit: ^limit
    )
  end

  @doc """
  Advances the agent's cursor to `seq` (never backwards) and prunes events the
  agent has now acknowledged. Returns the resulting cursor.
  """
  def ack(agent_id, seq) when is_binary(agent_id) and is_integer(seq) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    on_conflict =
      from c in EventCursor,
        update: [
          set: [
            acked_seq: fragment("GREATEST(?, EXCLUDED.acked_seq)", c.acked_seq),
            updated_at: ^now
          ]
        ]

    {:ok, %{cursor: cursor}} =
      Repo.transaction(fn ->
        Repo.insert_all(
          EventCursor,
          [[agent_id: agent_id, acked_seq: seq, inserted_at: now, updated_at: now]],
          on_conflict: on_conflict,
          conflict_target: :agent_id
        )

        acked = cursor(agent_id)

        Repo.delete_all(
          from e in AgentEvent, where: e.agent_id == ^agent_id and e.seq <= ^acked
        )

        %{cursor: acked}
      end)

    cursor
  end
end
