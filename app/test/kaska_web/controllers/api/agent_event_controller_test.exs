defmodule KaskaWeb.Api.AgentEventControllerTest do
  use KaskaWeb.ConnCase, async: true

  alias Kaska.{Accounts, AgentEvents, Agents, ApiTokens, Projects}

  defp user_fixture do
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

    {:ok, %{agent: agent, token: agent_token}} =
      Agents.create_agent(owner.id, project.id, %{display_name: "Scout"})

    {:ok, agent_token_record, _} = ApiTokens.create_token(owner, "owner_token")

    %{
      owner: owner,
      project: project,
      agent: agent,
      agent_token: agent_token,
      owner_token: agent_token_record
    }
  end

  defp auth(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  describe "index" do
    setup :setup_project

    test "returns pending events for an agent", %{
      conn: conn,
      project: project,
      agent: agent,
      agent_token: agent_token
    } do
      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{"commented_by_id" => "some-id"}
        })

      conn = conn |> auth(agent_token) |> get(~p"/api/v1/agent/events")
      body = json_response(conn, 200)

      assert [returned] = body["events"]
      assert returned["id"] == event.id
      assert returned["event_type"] == "task_comment"
      assert returned["project_id"] == project.id
      assert body["cursor"] == event.id
    end

    test "returns empty list when no pending events", %{
      conn: conn,
      agent_token: agent_token
    } do
      conn = conn |> auth(agent_token) |> get(~p"/api/v1/agent/events")
      body = json_response(conn, 200)
      assert body["events"] == []
      assert body["cursor"] == nil
    end

    test "does not return events for other agents", %{
      conn: conn,
      project: project,
      owner: owner,
      agent_token: agent_token
    } do
      {:ok, %{agent: other_agent}} =
        Agents.create_agent(owner.id, project.id, %{display_name: "Ranger"})

      {:ok, _} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: other_agent.id,
          payload: %{}
        })

      conn = conn |> auth(agent_token) |> get(~p"/api/v1/agent/events")
      body = json_response(conn, 200)
      assert body["events"] == []
    end

    test "non-agent gets 403", %{conn: conn, owner: owner} do
      {:ok, owner_token, _} = ApiTokens.create_token(owner, "owner")

      conn = conn |> auth(owner_token) |> get(~p"/api/v1/agent/events")
      assert json_response(conn, 403)["error"] == "not an agent"
    end

    test "unauthenticated gets 401", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/agent/events")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "returns events after since cursor", %{
      conn: conn,
      project: project,
      agent: agent,
      agent_token: agent_token
    } do
      {:ok, event1} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{}
        })

      {:ok, event2} =
        AgentEvents.emit(%{
          event_type: "comment_reply",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{}
        })

      conn =
        conn
        |> auth(agent_token)
        |> get(~p"/api/v1/agent/events?since=#{event1.id}")

      body = json_response(conn, 200)
      assert [returned] = body["events"]
      assert returned["id"] == event2.id
    end
  end

  describe "ack" do
    setup :setup_project

    test "acks an event by id", %{
      conn: conn,
      project: project,
      agent: agent,
      agent_token: agent_token
    } do
      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{}
        })

      conn = conn |> auth(agent_token) |> post(~p"/api/v1/agent/events/#{event.id}/ack")
      assert json_response(conn, 200)["ok"] == true

      conn = conn |> recycle() |> auth(agent_token) |> get(~p"/api/v1/agent/events")
      assert json_response(conn, 200)["events"] == []
    end

    test "returns 404 for unknown event id", %{
      conn: conn,
      agent_token: agent_token
    } do
      fake_id = Ecto.UUID.generate()
      conn = conn |> auth(agent_token) |> post(~p"/api/v1/agent/events/#{fake_id}/ack")
      assert json_response(conn, 404)["error"] == "event not found"
    end

    test "cannot ack another agent's event", %{
      conn: conn,
      project: project,
      owner: owner,
      agent_token: agent_token
    } do
      {:ok, %{agent: other_agent}} =
        Agents.create_agent(owner.id, project.id, %{display_name: "Ranger"})

      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: other_agent.id,
          payload: %{}
        })

      conn = conn |> auth(agent_token) |> post(~p"/api/v1/agent/events/#{event.id}/ack")
      assert json_response(conn, 404)["error"] == "event not found"
    end

    test "non-agent gets 403 on ack", %{conn: conn, project: project, agent: agent, owner: owner} do
      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{}
        })

      {:ok, owner_token, _} = ApiTokens.create_token(owner, "owner")
      conn = conn |> auth(owner_token) |> post(~p"/api/v1/agent/events/#{event.id}/ack")
      assert json_response(conn, 403)["error"] == "not an agent"
    end
  end
end
