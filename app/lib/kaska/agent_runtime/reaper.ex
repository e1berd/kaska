defmodule Kaska.AgentRuntime.Reaper do
  @moduledoc "Periodically finishes agent runs the supervisor lost track of."

  use GenServer

  require Logger

  alias Kaska.AgentRuntime.Dispatcher

  @interval :timer.minutes(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    schedule()
    {:ok, nil}
  end

  @impl true
  def handle_info(:reap, state) do
    case Dispatcher.reap_stale() do
      0 -> :ok
      count -> Logger.warning("reaped #{count} stale agent run(s)")
    end

    schedule()
    {:noreply, state}
  end

  defp schedule, do: Process.send_after(self(), :reap, @interval)
end
