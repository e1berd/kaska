defmodule Kaska.AgentRuntime.DispatcherTest do
  use Kaska.DataCase, async: true

  import Kaska.AgentRuntimeFixtures

  alias Kaska.{AgentRuntime, ApiTokens, Repo}
  alias Kaska.AgentRuntime.{AgentRun, Dispatcher, SupervisorClient}

  setup do
    board_with_code_agent()
  end

  defp stub_supervisor(fun), do: Req.Test.stub(SupervisorClient, fun)

  describe "dispatch/1" do
    test "starts the container with a run PAT and marks the run running", %{
      run: run,
      agent: agent,
      project: project
    } do
      test_pid = self()

      stub_supervisor(fn conn ->
        assert conn.request_path == "/runs"

        assert ["Bearer dev_only_agent_supervisor_secret"] =
                 Plug.Conn.get_req_header(conn, "authorization")

        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:start_payload, Jason.decode!(body)})
        Req.Test.json(conn, %{container_id: "c-123"})
      end)

      assert {:ok, running} = Dispatcher.dispatch(run)
      assert running.status == "running"
      assert running.container_id == "c-123"
      assert running.api_token_id

      assert_receive {:start_payload, payload}
      assert payload["run_id"] == run.id
      assert payload["callback_url"] =~ "/agent_runs/#{run.id}"
      assert payload["limits"]["walltime_seconds"] > 0
      assert payload["env"]["LLM_API_KEY"] == "sk-secret-value"
      assert payload["env"]["PROJECT_SLUG"] == project.slug
      assert {:ok, %{id: agent_id}} = ApiTokens.verify_token(payload["env"]["KASKA_PAT"])
      assert agent_id == agent.id
    end

    test "fails the run and revokes the PAT when the supervisor errors", %{run: run} do
      test_pid = self()

      stub_supervisor(fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:pat, Jason.decode!(body)["env"]["KASKA_PAT"]})
        Plug.Conn.send_resp(conn, 500, "boom")
      end)

      assert {:ok, failed} = Dispatcher.dispatch(run)
      assert failed.status == "failed"
      assert failed.exit_reason =~ "supervisor"
      assert_receive {:pat, pat}
      assert :error = ApiTokens.verify_token(pat)
    end

    test "fails the run when the supervisor is unreachable", %{run: run} do
      stub_supervisor(&Req.Test.transport_error(&1, :econnrefused))
      assert {:ok, %{status: "failed"}} = Dispatcher.dispatch(run)
    end

    test "stops the fresh container when the run was stopped meanwhile", %{run: run} do
      test_pid = self()
      {:ok, _} = AgentRuntime.finish_run(run, %{status: "stopped"})

      stub_supervisor(fn conn ->
        send(test_pid, {:called, conn.request_path})
        Req.Test.json(conn, %{container_id: "c-1"})
      end)

      assert {:error, :not_active} = Dispatcher.dispatch(%{run | status: "pending"})
      assert_receive {:called, "/runs"}
      stop_path = "/runs/#{run.id}/stop"
      assert_receive {:called, ^stop_path}
    end

    test "ignores runs that are not pending", %{run: run} do
      assert {:error, :not_active} = Dispatcher.dispatch(%{run | status: "running"})
    end
  end

  describe "stop/1" do
    test "marks a running run stopped and kills the container", %{run: run} do
      {:ok, running} = AgentRuntime.mark_running(run, "c-1", nil)
      test_pid = self()

      stub_supervisor(fn conn ->
        send(test_pid, {:called, conn.request_path})
        Req.Test.json(conn, %{})
      end)

      assert {:ok, %{status: "stopped"}} = Dispatcher.stop(running)
      stop_path = "/runs/#{run.id}/stop"
      assert_receive {:called, ^stop_path}
    end

    test "stops a pending run without calling the supervisor", %{run: run} do
      stub_supervisor(fn _conn -> flunk("supervisor must not be called") end)
      assert {:ok, %{status: "stopped"}} = Dispatcher.stop(run)
    end
  end

  describe "report_exit/2" do
    setup %{run: run} do
      {:ok, running} = AgentRuntime.mark_running(run, "c-1", nil)
      %{running: running}
    end

    test "exit code 0 succeeds", %{running: running} do
      assert {:ok, %{status: "succeeded", exit_code: 0}} =
               Dispatcher.report_exit(running, %{"outcome" => "exited", "exit_code" => 0})
    end

    test "non-zero exit fails", %{running: running} do
      assert {:ok, %{status: "failed", exit_code: 2}} =
               Dispatcher.report_exit(running, %{"outcome" => "exited", "exit_code" => 2})
    end

    test "timed_out keeps its reason", %{running: running} do
      assert {:ok, %{status: "timed_out", exit_reason: "walltime"}} =
               Dispatcher.report_exit(running, %{"outcome" => "timed_out", "reason" => "walltime"})
    end

    test "rejects unknown outcomes", %{running: running} do
      assert {:error, :unknown_outcome} = Dispatcher.report_exit(running, %{"outcome" => "meh"})
      assert {:error, :unknown_outcome} = Dispatcher.report_exit(running, %{})
    end
  end

  describe "reap_stale/1" do
    test "times out running runs past walltime and fails old pending runs", %{
      run: run,
      agent: agent,
      owner: owner,
      project: project
    } do
      {:ok, running} = AgentRuntime.mark_running(run, "c-1", nil)

      long_ago =
        DateTime.utc_now() |> DateTime.add(-86_400, :second) |> DateTime.truncate(:second)

      Repo.update_all(from(r in AgentRun, where: r.id == ^running.id),
        set: [started_at: long_ago]
      )

      {_p, [todo | _], _t} = Kaska.Projects.board_snapshot(project.id)

      {:ok, other_task} =
        Kaska.Projects.create_task(
          project.id,
          todo.id,
          %{title: "T2", assignee_id: agent.id},
          owner.id
        )

      {:ok, pending} = AgentRuntime.request_run(agent, other_task, owner.id)

      Repo.update_all(from(r in AgentRun, where: r.id == ^pending.id),
        set: [inserted_at: long_ago]
      )

      stub_supervisor(&Req.Test.json(&1, %{}))

      assert Dispatcher.reap_stale() == 2
      assert AgentRuntime.get_run(running.id).status == "timed_out"
      assert AgentRuntime.get_run(pending.id).status == "failed"
    end

    test "leaves fresh runs alone", %{run: run} do
      {:ok, _} = AgentRuntime.mark_running(run, "c-1", nil)
      assert Dispatcher.reap_stale() == 0
    end
  end
end
