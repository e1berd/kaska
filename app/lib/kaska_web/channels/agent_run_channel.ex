defmodule KaskaWeb.AgentRunChannel do
  @moduledoc """
  `agent_run:<run_id>` — the live console of one agent run. Anyone who can see
  the run's board may join. The join reply carries the run and its stored log
  tail; afterwards the channel pushes `log` (`%{chunk}`) for new output and
  `run` when the run's status changes.
  """

  use Phoenix.Channel

  alias Kaska.{AgentRuntime, Projects}
  alias Kaska.AgentRuntime.AgentRun
  alias KaskaWeb.AgentViews

  @impl true
  def join("agent_run:" <> run_id, _payload, socket) do
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id

    with %AgentRun{} = run <- AgentRuntime.get_run(run_id),
         project when not is_nil(project) <- Projects.get_project(run.project_id),
         true <- Projects.board_accessible?(project, user_id) do
      :ok = Phoenix.PubSub.subscribe(Kaska.PubSub, AgentRuntime.run_topic(run.id))
      {:ok, %{run: AgentViews.run(run), log_tail: run.log_tail}, socket}
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_info({:agent_run_log, _run_id, chunk}, socket) do
    push(socket, "log", %{chunk: chunk})
    {:noreply, socket}
  end

  def handle_info({:agent_run_updated, %AgentRun{} = run}, socket) do
    push(socket, "run", AgentViews.run(run))
    {:noreply, socket}
  end
end
