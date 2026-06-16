defmodule KaskaWeb.Api.EventController do
  @moduledoc """
  Agent-facing event stream. `index` long-polls the agent's outbox: it returns
  pending events immediately, or parks (subscribed to the agent's PubSub topic)
  until one arrives or `wait` seconds elapse. `ack` advances the durable cursor
  so acknowledged events stop being redelivered.
  """
  use KaskaWeb, :controller

  alias Kaska.AgentEvents
  alias KaskaWeb.Api.Serializer

  action_fallback KaskaWeb.Api.FallbackController

  @max_wait_ms 50_000
  @default_limit 100
  @max_limit 200

  def index(conn, params) do
    agent = conn.assigns.current_user
    wait_ms = parse_wait(params)
    limit = parse_limit(params)
    after_seq = parse_after(params, agent.id)

    events = wait_for_events(agent.id, after_seq, limit, wait_ms)

    cursor =
      case events do
        [] -> after_seq
        _ -> List.last(events).seq
      end

    json(conn, %{events: Enum.map(events, &Serializer.event/1), cursor: cursor})
  end

  def ack(conn, params) do
    agent = conn.assigns.current_user

    case parse_int(params["cursor"] || params["seq"]) do
      nil -> {:error, :invalid_cursor}
      seq -> json(conn, %{cursor: AgentEvents.ack(agent.id, seq)})
    end
  end

  defp wait_for_events(agent_id, after_seq, limit, wait_ms) do
    case AgentEvents.pending(agent_id, after_seq, limit) do
      [] when wait_ms > 0 ->
        AgentEvents.subscribe(agent_id)

        try do
          case AgentEvents.pending(agent_id, after_seq, limit) do
            [] ->
              receive do
                {:agent_event, _seq} -> :ok
              after
                wait_ms -> :timeout
              end

              AgentEvents.pending(agent_id, after_seq, limit)

            events ->
              events
          end
        after
          AgentEvents.unsubscribe(agent_id)
        end

      events ->
        events
    end
  end

  defp parse_wait(params) do
    params["wait"]
    |> parse_int()
    |> case do
      nil -> 0
      n when n <= 0 -> 0
      n -> min(n * 1000, @max_wait_ms)
    end
  end

  defp parse_limit(params) do
    case parse_int(params["limit"]) do
      nil -> @default_limit
      n when n <= 0 -> @default_limit
      n -> min(n, @max_limit)
    end
  end

  defp parse_after(params, agent_id) do
    case parse_int(params["after"]) do
      nil -> AgentEvents.cursor(agent_id)
      n when n < 0 -> AgentEvents.cursor(agent_id)
      n -> n
    end
  end

  defp parse_int(nil), do: nil
  defp parse_int(n) when is_integer(n), do: n

  defp parse_int(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_int(_), do: nil
end
