defmodule KaskaWeb.AgentChannelsTest do
  use KaskaWeb.ChannelCase, async: false

  import Kaska.AgentRuntimeFixtures

  alias Kaska.{Accounts, AgentRuntime}
  alias Kaska.AgentRuntime.SupervisorClient

  setup do
    Req.Test.set_req_test_to_shared()
    board_with_code_agent()
  end

  defp stranger do
    email = "stranger#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  describe "agents:user" do
    test "only the owner joins; the reply never contains the api key", %{owner: owner} do
      assert {:error, %{reason: "unauthorized"}} =
               stranger()
               |> user_socket()
               |> subscribe_and_join(KaskaWeb.AgentsChannel, "agents:user:#{owner.id}")

      assert {:ok, reply, _socket} =
               owner
               |> user_socket()
               |> subscribe_and_join(KaskaWeb.AgentsChannel, "agents:user:#{owner.id}")

      assert [%{config: %{ready: true, api_key_set: true, api_key_hint: "alue"}}] = reply.agents
      refute inspect(reply) =~ "sk-secret-value"
      assert Enum.any?(reply.presets, &(&1.slug == "deepseek"))
    end

    test "creates, configures and deletes an agent", %{owner: owner} do
      {:ok, _reply, socket} =
        owner
        |> user_socket()
        |> subscribe_and_join(KaskaWeb.AgentsChannel, "agents:user:#{owner.id}")

      ref = push(socket, "create_agent", %{"display_name" => "Reviewer"})
      assert_reply ref, :ok, %{agent: %{id: id, config: %{ready: false, missing: missing}}}
      assert :provider in missing

      ref =
        push(socket, "update_agent", %{
          "id" => id,
          "provider_preset" => "anthropic",
          "model" => "claude-opus-5",
          "api_key" => "sk-ant-0123456789"
        })

      assert_reply ref, :ok, %{agent: %{config: %{ready: true, provider_kind: "anthropic"}}}

      ref = push(socket, "delete_agent", %{"id" => id})
      assert_reply ref, :ok, %{id: ^id}
    end

    test "pushes run updates of the owner's agents", %{owner: owner, run: run} do
      {:ok, _reply, _socket} =
        owner
        |> user_socket()
        |> subscribe_and_join(KaskaWeb.AgentsChannel, "agents:user:#{owner.id}")

      {:ok, _} = AgentRuntime.mark_running(run, "c-1", nil)
      assert_push "agent_run_updated", %{run: %{status: "running", task_title: "T"}}
    end
  end

  describe "board runs" do
    test "starts and stops a run on the assigned agent", %{
      owner: owner,
      project: project,
      task: task,
      run: pending
    } do
      {:ok, _} = AgentRuntime.finish_run(pending, %{status: "stopped"})
      Req.Test.stub(SupervisorClient, &Req.Test.json(&1, %{container_id: "c-9"}))

      {:ok, reply, socket} =
        owner
        |> user_socket()
        |> subscribe_and_join(KaskaWeb.BoardChannel, "board:#{project.id}")

      assert [%{status: "stopped"}] = reply.agent_runs
      assert Enum.any?(reply.users, &match?(%{agent: %{ready: true}}, &1))

      ref = push(socket, "start_agent_run", %{"task_id" => task.id})
      assert_reply ref, :ok, %{id: run_id, status: "pending"}
      assert_push "agent_run_updated", %{id: ^run_id, status: "running"}, 2_000

      ref = push(socket, "stop_agent_run", %{"id" => run_id})
      assert_reply ref, :ok, %{status: "stopped"}

      ref = push(socket, "list_task_runs", %{"task_id" => task.id})
      assert_reply ref, :ok, %{runs: [%{id: ^run_id}, _]}
    end

    test "a second start while a run is active is refused", %{
      owner: owner,
      project: project,
      task: task
    } do
      {:ok, _reply, socket} =
        owner
        |> user_socket()
        |> subscribe_and_join(KaskaWeb.BoardChannel, "board:#{project.id}")

      ref = push(socket, "start_agent_run", %{"task_id" => task.id})
      assert_reply ref, :error, %{message: "already_running"}
    end
  end

  describe "agent_run" do
    test "members get the log tail and live chunks, strangers are refused", %{
      owner: owner,
      run: run
    } do
      {:ok, running} = AgentRuntime.mark_running(run, "c-1", nil)
      {:ok, _} = AgentRuntime.append_log(running, "line one\n")

      assert {:error, %{reason: "not_found"}} =
               stranger()
               |> user_socket()
               |> subscribe_and_join(KaskaWeb.AgentRunChannel, "agent_run:#{run.id}")

      assert {:ok, %{log_tail: "line one\n", run: %{status: "running"}}, _socket} =
               owner
               |> user_socket()
               |> subscribe_and_join(KaskaWeb.AgentRunChannel, "agent_run:#{run.id}")

      {:ok, _} = AgentRuntime.append_log(running, "line two\n")
      assert_push "log", %{chunk: "line two\n"}
    end
  end
end
