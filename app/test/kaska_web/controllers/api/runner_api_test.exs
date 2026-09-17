defmodule KaskaWeb.Api.RunnerApiTest do
  use KaskaWeb.ConnCase, async: true

  import Kaska.AgentRuntimeFixtures

  alias Kaska.{AgentRuntime, ApiTokens, Projects}

  setup %{conn: conn} do
    fixtures = board_with_code_agent()
    {:ok, pat, token_id} = AgentRuntime.issue_run_token(fixtures.run)
    {:ok, running} = AgentRuntime.mark_running(fixtures.run, "c-1", token_id)
    authed = put_req_header(conn, "authorization", "Bearer #{pat}")
    Map.merge(fixtures, %{pat: pat, running: running, authed: authed})
  end

  defp task_path(project, task), do: "/api/v1/p/#{project.slug}/tasks/#{task.id}"

  describe "authentication" do
    test "rejects missing tokens and tokens of finished runs", %{
      conn: conn,
      authed: authed,
      project: project,
      task: task,
      running: running
    } do
      assert conn |> get(task_path(project, task)) |> json_response(401)

      {:ok, _} = AgentRuntime.finish_run(running, %{status: "succeeded", exit_code: 0})
      assert authed |> get(task_path(project, task)) |> json_response(401)
    end

    test "rejects a live token that does not belong to an active run", %{
      conn: conn,
      agent: agent,
      project: project,
      task: task
    } do
      {:ok, stray, _} = ApiTokens.create_token(agent, "stray")

      assert conn
             |> put_req_header("authorization", "Bearer #{stray}")
             |> get(task_path(project, task))
             |> json_response(401)
    end

    test "confines the token to the run's project and task", %{
      authed: authed,
      project: project,
      owner: owner
    } do
      {_p, [todo | _], _t} = Projects.board_snapshot(project.id)
      {:ok, other} = Projects.create_task(project.id, todo.id, %{title: "Other"}, owner.id)

      assert authed |> get(task_path(project, other)) |> json_response(403)
      assert authed |> get("/api/v1/p/elsewhere") |> json_response(403)
    end
  end

  test "reads the project with agent instructions and columns", %{
    authed: authed,
    project: project
  } do
    assert %{"project" => %{"slug" => slug, "columns" => [_ | _]}} =
             authed |> get("/api/v1/p/#{project.slug}") |> json_response(200)

    assert slug == project.slug
  end

  test "reads, updates and moves the run's task", %{
    authed: authed,
    project: project,
    task: task
  } do
    assert %{"task" => %{"title" => "T", "body" => ""}} =
             authed |> get(task_path(project, task)) |> json_response(200)

    assert %{"task" => %{"title" => "Renamed", "body" => "**done**"}} =
             authed
             |> patch(task_path(project, task), %{
               title: "Renamed",
               body: "**done**",
               assignee_id: nil
             })
             |> json_response(200)

    assert Projects.get_task(task.id).assignee_id == task.assignee_id

    {_p, [_todo, in_progress | _], _t} = Projects.board_snapshot(project.id)

    assert %{"task" => %{"column" => %{"id" => column_id}}} =
             authed
             |> post("#{task_path(project, task)}/move", %{column_id: in_progress.id})
             |> json_response(200)

    assert column_id == in_progress.id
  end

  test "posts a comment as the agent", %{authed: authed, project: project, task: task} do
    assert %{"comment" => %{"body" => "Progress", "author" => %{"display_name" => "Coder"}}} =
             authed
             |> post("#{task_path(project, task)}/comments", %{body: "Progress"})
             |> json_response(201)
  end
end
