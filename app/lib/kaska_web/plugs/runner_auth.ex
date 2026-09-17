defmodule KaskaWeb.Plugs.RunnerAuth do
  @moduledoc """
  Authenticates `/api/v1` requests from an agent runner container. The bearer
  token must belong to an active `Kaska.AgentRuntime.AgentRun`, and the request
  is confined to that run: the `:project_slug` must be the run's project and a
  task id in the path (`:id` or `:task_id`) must be the run's task.

  Assigns `:current_user` (the agent), `:agent_run` and `:project`. Replies
  `401` for a missing, revoked or finished-run token and `403` outside the
  run's scope.
  """

  import Plug.Conn

  alias Kaska.{AgentRuntime, ApiTokens, Projects}
  alias Kaska.AgentRuntime.AgentRun
  alias Kaska.Projects.Project

  def init(opts), do: opts

  def call(conn, _opts) do
    case authenticate(conn) do
      {:ok, agent, run, project} ->
        if in_scope?(conn.path_params, run, project) do
          conn
          |> assign(:current_user, agent)
          |> assign(:agent_run, run)
          |> assign(:project, project)
        else
          halt_json(conn, 403, %{error: "forbidden"})
        end

      :error ->
        halt_json(conn, 401, %{error: "unauthorized"})
    end
  end

  defp authenticate(conn) do
    with ["Bearer " <> raw] <- get_req_header(conn, "authorization"),
         {:ok, token, agent} <- ApiTokens.resolve_token(String.trim(raw)),
         %AgentRun{} = run <- AgentRuntime.active_run_for_token(token.id),
         %Project{} = project <- Projects.get_project(run.project_id) do
      {:ok, agent, run, project}
    else
      _ -> :error
    end
  end

  defp in_scope?(params, %AgentRun{task_id: task_id}, %Project{slug: slug}) do
    params["project_slug"] == slug and
      Map.get(params, "id", task_id) == task_id and
      Map.get(params, "task_id", task_id) == task_id
  end

  defp halt_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
