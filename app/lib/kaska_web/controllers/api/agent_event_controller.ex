defmodule KaskaWeb.Api.AgentEventController do
  use KaskaWeb, :controller

  alias Kaska.AgentEvents

  plug KaskaWeb.Plugs.ApiAuth

  @long_poll_timeout_ms 30_000

  def index(conn, params) do
    agent = conn.assigns.current_user

    if agent.is_agent do
      since = parse_since(params["since"])
      limit = min(parse_limit(params["limit"]), 100)

      events = AgentEvents.pending_events(agent.id, since: since, limit: limit)

      if events == [] and params["wait"] != "false" do
        wait_for_events(conn, agent, since, limit)
      else
        json(conn, %{events: Enum.map(events, &event_view/1), cursor: cursor(events)})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "not an agent"})
    end
  end

  def ack(conn, %{"id" => id}) do
    agent = conn.assigns.current_user

    if agent.is_agent do
      case AgentEvents.ack_event(agent.id, id) do
        {:ok, :acked} ->
          json(conn, %{ok: true})

        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "event not found"})
      end
    else
      conn |> put_status(:forbidden) |> json(%{error: "not an agent"})
    end
  end

  defp wait_for_events(conn, agent, since, limit) do
    ref = make_ref()

    Phoenix.PubSub.subscribe(Kaska.PubSub, AgentEvents.topic_for(agent.id))

    timer_ref =
      Process.send_after(self(), {:poll_timeout, ref}, @long_poll_timeout_ms)

    receive do
      {:poll_timeout, ^ref} ->
        Process.demonitor(ref, [:flush])
        events = AgentEvents.pending_events(agent.id, since: since, limit: limit)
        json(conn, %{events: Enum.map(events, &event_view/1), cursor: cursor(events)})

      {:agent_event_new, _event} ->
        Process.cancel_timer(timer_ref)
        events = AgentEvents.pending_events(agent.id, since: since, limit: limit)
        json(conn, %{events: Enum.map(events, &event_view/1), cursor: cursor(events)})
    after
      @long_poll_timeout_ms + 1000 ->
        events = AgentEvents.pending_events(agent.id, since: since, limit: limit)
        json(conn, %{events: Enum.map(events, &event_view/1), cursor: cursor(events)})
    end
  end

  defp parse_since(nil), do: nil

  defp parse_since(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} ->
        id

      :error ->
        case DateTime.from_iso8601(value) do
          {:ok, dt, _} -> DateTime.truncate(dt, :second)
          _ -> nil
        end
    end
  end

  defp parse_since(_), do: nil

  defp parse_limit(nil), do: 50
  defp parse_limit(value) when is_integer(value) and value > 0, do: value

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> n
      _ -> 50
    end
  end

  defp parse_limit(_), do: 50

  defp cursor([]), do: nil

  defp cursor(events) do
    last = List.last(events)
    last.id
  end

  defp event_view(event) do
    %{
      id: event.id,
      event_type: event.event_type,
      payload: event.payload,
      project_id: event.project_id,
      task_id: event.task_id,
      comment_id: event.comment_id,
      inserted_at: event.inserted_at
    }
  end
end
