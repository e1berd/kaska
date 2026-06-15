defmodule KaskaWeb.Api.TaskControllerTest do
  use KaskaWeb.ConnCase, async: true

  alias Kaska.{Accounts, ApiTokens, Projects}

  defp user_fixture(_attrs \\ %{}) do
    email = "user#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  defp setup_project(_context) do
    owner = user_fixture()

    {:ok, project} =
      Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    {_project, [todo, in_progress | _], _tasks} = Projects.board_snapshot(project.id)

    {:ok, task} =
      Projects.create_task(project.id, todo.id, %{title: "First"}, owner.id)

    {:ok, token, _} = ApiTokens.create_token(owner, "agent")

    %{
      owner: owner,
      project: project,
      todo: todo,
      in_progress: in_progress,
      task: task,
      token: token
    }
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  describe "authentication" do
    setup :setup_project

    test "rejects a request without a token", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/v1/p/#{project.slug}/tasks")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "rejects a non-member token", %{conn: conn, project: project} do
      outsider = user_fixture()
      {:ok, token, _} = ApiTokens.create_token(outsider, "spy")

      conn = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/tasks")
      assert json_response(conn, 403)["error"] == "forbidden"
    end

    test "404 for an unknown project", %{conn: conn, token: token} do
      conn = conn |> auth(token) |> get(~p"/api/v1/p/nope/tasks")
      assert json_response(conn, 404)["error"] == "project_not_found"
    end
  end

  describe "index" do
    setup :setup_project

    test "lists tasks with markdown body by default", %{
      conn: conn,
      project: project,
      token: token
    } do
      conn = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/tasks")
      body = json_response(conn, 200)

      assert [task] = body["tasks"]
      assert task["title"] == "First"
      assert task["body_format"] == "markdown"
      assert is_binary(task["body"])
      assert task["comments"] == []
      assert task["column"]["name"] == "Todo"
    end

    test "task_format=json returns the raw tiptap document", %{
      conn: conn,
      project: project,
      token: token,
      task: task
    } do
      {:ok, _} = Projects.update_task(task, %{body_doc: Kaska.TaskBody.from_markdown("## Hi")})

      conn = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/tasks?task_format=json")
      assert [task_json] = json_response(conn, 200)["tasks"]
      assert task_json["body_format"] == "json"
      assert task_json["body"]["type"] == "doc"
    end
  end

  describe "update" do
    setup :setup_project

    test "writes a markdown body into the stored document", %{
      conn: conn,
      project: project,
      token: token,
      task: task
    } do
      conn =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/p/#{project.slug}/tasks/#{task.id}", %{
          title: "Renamed",
          body: "Hello **world**"
        })

      body = json_response(conn, 200)["task"]
      assert body["title"] == "Renamed"
      assert body["body"] == "Hello **world**"

      reloaded = Projects.get_task(task.id)
      assert reloaded.title == "Renamed"
      assert %{"type" => "doc"} = reloaded.body_doc
    end

    test "404 for a task outside the project", %{conn: conn, project: project, token: token} do
      conn =
        conn
        |> auth(token)
        |> patch(~p"/api/v1/p/#{project.slug}/tasks/#{Ecto.UUID.generate()}", %{title: "x"})

      assert json_response(conn, 404)
    end
  end

  describe "move" do
    setup :setup_project

    test "moves a task to another column", %{
      conn: conn,
      project: project,
      token: token,
      task: task,
      in_progress: in_progress
    } do
      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/p/#{project.slug}/tasks/#{task.id}/move", %{column_id: in_progress.id})

      body = json_response(conn, 200)["task"]
      assert body["column"]["id"] == in_progress.id

      assert Projects.get_task(task.id).column_id == in_progress.id
    end
  end

  describe "comments" do
    setup :setup_project

    test "creates and lists a comment", %{conn: conn, project: project, token: token, task: task} do
      create =
        conn
        |> auth(token)
        |> post(~p"/api/v1/p/#{project.slug}/tasks/#{task.id}/comments", %{body: "is this ready?"})

      created = json_response(create, 201)["comment"]
      assert created["body"] == "is this ready?"
      assert created["author"]["email"]

      list = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/tasks/#{task.id}/comments")
      assert [listed] = json_response(list, 200)["comments"]
      assert listed["id"] == created["id"]
    end

    test "rejects an empty comment body", %{
      conn: conn,
      project: project,
      token: token,
      task: task
    } do
      conn =
        conn
        |> auth(token)
        |> post(~p"/api/v1/p/#{project.slug}/tasks/#{task.id}/comments", %{body: "   "})

      assert json_response(conn, 422)["errors"]
    end
  end

  describe "board reads" do
    setup :setup_project

    test "lists columns, task types and members", %{conn: conn, project: project, token: token} do
      columns = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/columns")

      assert ["Todo", "In Progress", "Done"] =
               Enum.map(json_response(columns, 200)["columns"], & &1["name"])

      members = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/members")
      assert [_owner] = json_response(members, 200)["members"]

      types = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/task_types")
      assert json_response(types, 200)["task_types"] == []
    end

    test "lists the token's projects", %{conn: conn, project: project, token: token} do
      resp = conn |> auth(token) |> get(~p"/api/v1/projects")
      assert [listed] = json_response(resp, 200)["projects"]
      assert listed["slug"] == project.slug
    end

    test "exposes agent instructions and column descriptions", %{
      conn: conn,
      project: project,
      token: token,
      todo: todo
    } do
      {:ok, _} =
        Projects.update_project(project, %{agent_instructions: "Move work along the board."})

      {:ok, _} =
        Projects.rename_column(todo, %{description: "Backlog. Pull from here into In Progress."})

      overview = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}")
      body = json_response(overview, 200)["project"]

      assert body["agent_instructions"] == "Move work along the board."
      assert body["slug"] == project.slug

      todo_view = Enum.find(body["columns"], &(&1["id"] == todo.id))
      assert todo_view["description"] == "Backlog. Pull from here into In Progress."

      columns = conn |> auth(token) |> get(~p"/api/v1/p/#{project.slug}/columns")
      listed = Enum.find(json_response(columns, 200)["columns"], &(&1["id"] == todo.id))
      assert listed["description"] == "Backlog. Pull from here into In Progress."
    end
  end
end
