defmodule KaskaWeb.Internal.AgentRunControllerTest do
  use KaskaWeb.ConnCase, async: true

  import Kaska.AgentRuntimeFixtures

  alias Kaska.AgentRuntime

  setup %{conn: conn} do
    fixtures = board_with_code_agent()
    {:ok, running} = AgentRuntime.mark_running(fixtures.run, "c-1", nil)

    authed =
      put_req_header(conn, "authorization", "Bearer dev_only_agent_supervisor_secret")

    Map.merge(fixtures, %{running: running, authed: authed})
  end

  describe "auth" do
    test "rejects missing and wrong secrets", %{conn: conn, running: running} do
      path = "/internal/agent_runs/#{running.id}/exit"
      assert conn |> post(path, %{outcome: "exited", exit_code: 0}) |> json_response(401)

      assert conn
             |> put_req_header("authorization", "Bearer nope")
             |> post(path, %{outcome: "exited", exit_code: 0})
             |> json_response(401)

      assert AgentRuntime.get_run(running.id).status == "running"
    end
  end

  describe "logs" do
    test "appends output and broadcasts the chunk", %{authed: authed, running: running} do
      Phoenix.PubSub.subscribe(Kaska.PubSub, AgentRuntime.run_topic(running.id))

      assert %{"status" => "running"} =
               authed
               |> post("/internal/agent_runs/#{running.id}/logs", %{chunk: "hello\n"})
               |> json_response(200)

      assert AgentRuntime.get_run(running.id).log_tail == "hello\n"
      run_id = running.id
      assert_receive {:agent_run_log, ^run_id, "hello\n"}
    end

    test "requires a chunk", %{authed: authed, running: running} do
      assert authed |> post("/internal/agent_runs/#{running.id}/logs", %{}) |> json_response(400)
    end

    test "unknown or malformed run ids are 404", %{authed: authed} do
      assert authed
             |> post("/internal/agent_runs/#{Ecto.UUID.generate()}/logs", %{chunk: "x"})
             |> json_response(404)

      assert authed |> post("/internal/agent_runs/nope/logs", %{chunk: "x"}) |> json_response(404)
    end
  end

  describe "exit" do
    test "finishes the run, repeated reports conflict", %{authed: authed, running: running} do
      path = "/internal/agent_runs/#{running.id}/exit"

      assert %{"status" => "succeeded"} =
               authed |> post(path, %{outcome: "exited", exit_code: 0}) |> json_response(200)

      assert %{"error" => "not_active"} =
               authed |> post(path, %{outcome: "exited", exit_code: 1}) |> json_response(409)
    end

    test "unknown outcome is a bad request", %{authed: authed, running: running} do
      assert authed
             |> post("/internal/agent_runs/#{running.id}/exit", %{outcome: "exploded"})
             |> json_response(400)
    end
  end
end
