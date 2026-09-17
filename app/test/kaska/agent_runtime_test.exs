defmodule Kaska.AgentRuntimeTest do
  use Kaska.DataCase, async: true

  alias Kaska.{Accounts, Agents, AgentRuntime, ApiTokens, Projects, Repo}
  alias Kaska.AgentRuntime.AgentConfig

  defp owner_fixture do
    email = "owner#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  defp ready_attrs do
    %{
      provider_preset: "deepseek",
      model: "deepseek-chat",
      api_key: "sk-secret-value"
    }
  end

  defp setup_board(_context) do
    owner = owner_fixture()

    {:ok, project} =
      Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    {:ok, agent} = Agents.create_agent(owner.id, %{display_name: "Coder"})
    {:ok, _} = Agents.assign_to_project(agent, project.id)
    {_p, [todo | _], _t} = Projects.board_snapshot(project.id)

    {:ok, task} =
      Projects.create_task(project.id, todo.id, %{title: "T", assignee_ids: [agent.id]}, owner.id)

    %{owner: owner, project: project, agent: agent, task: task, column: todo}
  end

  describe "agent config" do
    setup :setup_board

    test "an unconfigured agent is not ready and says what is missing", %{agent: agent} do
      config = AgentRuntime.config_for(agent)
      refute AgentConfig.ready?(config)
      assert AgentConfig.missing(config) == [:provider, :model]
    end

    test "preset fills provider kind and base url", %{agent: agent} do
      assert {:ok, config} = AgentRuntime.upsert_config(agent, ready_attrs())
      assert config.provider_kind == "openai_compatible"
      assert config.base_url == "https://api.deepseek.com/v1"
      assert AgentConfig.ready?(config)
    end

    test "api key is encrypted at rest and decrypted on load", %{agent: agent} do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())

      [raw] =
        Repo.query!("SELECT encrypted_api_key FROM agent_configs WHERE agent_id = $1", [
          Ecto.UUID.dump!(agent.id)
        ]).rows
        |> List.flatten()
        |> List.wrap()

      refute raw =~ "sk-secret-value"
      assert AgentRuntime.get_config(agent.id).encrypted_api_key == "sk-secret-value"
    end

    test "updating without api_key keeps the stored key", %{agent: agent} do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())
      assert {:ok, updated} = AgentRuntime.upsert_config(agent, %{model: "deepseek-reasoner"})
      assert updated.encrypted_api_key == "sk-secret-value"
      assert AgentRuntime.api_key_set?(updated)
    end

    test "a hosted provider without a key saves but is not ready", %{agent: agent} do
      attrs = Map.delete(ready_attrs(), :api_key)
      assert {:ok, config} = AgentRuntime.upsert_config(agent, attrs)
      assert AgentConfig.missing(config) == [:api_key]
    end

    test "switching preset replaces the base url unless one is given", %{agent: agent} do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())
      assert {:ok, config} = AgentRuntime.upsert_config(agent, %{provider_preset: "openai"})
      assert config.base_url == "https://api.openai.com/v1"

      assert {:ok, custom} =
               AgentRuntime.upsert_config(agent, %{
                 provider_preset: "custom",
                 base_url: "https://llm.example/v1"
               })

      assert custom.base_url == "https://llm.example/v1"
    end

    test "the key hint shows only the last characters", %{agent: agent} do
      {:ok, config} = AgentRuntime.upsert_config(agent, ready_attrs())
      assert AgentConfig.api_key_hint(config) == "alue"
    end

    test "local presets do not require an api key", %{agent: agent} do
      assert {:ok, config} =
               AgentRuntime.upsert_config(agent, %{
                 provider_preset: "ollama",
                 model: "qwen2.5-coder"
               })

      assert config.provider_kind == "ollama_local"
      refute AgentRuntime.api_key_set?(config)
      assert AgentConfig.ready?(config)
    end

    test "rejects unknown provider kinds", %{agent: agent} do
      assert {:error, changeset} =
               AgentRuntime.upsert_config(agent, %{provider_kind: "gemini_cli"})

      assert %{provider_kind: _} = errors_on(changeset)
    end
  end

  describe "request_run/4" do
    setup :setup_board

    test "refuses agents that are not configured", %{agent: agent, task: task, owner: owner} do
      assert {:error, :not_configured} = AgentRuntime.request_run(agent, task, owner.id)
    end

    test "refuses when the agent is not the assignee", %{agent: agent, task: task, owner: owner} do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())
      {:ok, unassigned} = Projects.update_task(task, %{assignee_ids: [owner.id]})
      assert {:error, :not_assigned} = AgentRuntime.request_run(agent, unassigned, owner.id)
    end

    test "creates a pending run and broadcasts it", %{agent: agent, task: task, owner: owner} do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())
      Phoenix.PubSub.subscribe(Kaska.PubSub, AgentRuntime.task_runs_topic(task.id))

      assert {:ok, run} = AgentRuntime.request_run(agent, task, owner.id)
      assert run.status == "pending"
      assert run.project_id == task.project_id
      assert_receive {:agent_run_updated, %{id: run_id}}
      assert run_id == run.id
    end

    test "allows only one active run per task", %{agent: agent, task: task, owner: owner} do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())
      assert {:ok, _} = AgentRuntime.request_run(agent, task, owner.id)
      assert {:error, :already_running} = AgentRuntime.request_run(agent, task, owner.id)
    end

    test "enforces the per-owner active run quota", %{
      agent: agent,
      owner: owner,
      project: project,
      column: column
    } do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())

      tasks =
        for i <- 1..(AgentRuntime.max_active_runs_per_owner() + 1) do
          {:ok, task} =
            Projects.create_task(
              project.id,
              column.id,
              %{title: "T#{i}", assignee_ids: [agent.id]},
              owner.id
            )

          task
        end

      {allowed, [over]} = Enum.split(tasks, -1)
      for task <- allowed, do: assert({:ok, _} = AgentRuntime.request_run(agent, task, owner.id))
      assert {:error, :quota_exceeded} = AgentRuntime.request_run(agent, over, owner.id)
    end
  end

  describe "run lifecycle" do
    setup :setup_board

    setup %{agent: agent, task: task, owner: owner} do
      {:ok, _} = AgentRuntime.upsert_config(agent, ready_attrs())
      {:ok, run} = AgentRuntime.request_run(agent, task, owner.id)
      %{run: run}
    end

    test "mark_running issues a token that authenticates as the agent, finish revokes it", %{
      run: run,
      agent: agent
    } do
      {:ok, pat, token_id} = AgentRuntime.issue_run_token(run)
      assert {:ok, running} = AgentRuntime.mark_running(run, "container-1", token_id)
      assert running.status == "running"
      assert running.started_at
      assert {:ok, %{id: agent_id}} = ApiTokens.verify_token(pat)
      assert agent_id == agent.id

      assert {:ok, finished} =
               AgentRuntime.finish_run(running, %{status: "succeeded", exit_code: 0})

      assert finished.finished_at
      assert :error = ApiTokens.verify_token(pat)
    end

    test "finishing twice is rejected without changing the run", %{run: run} do
      {:ok, _} = AgentRuntime.mark_running(run, "container-1", nil)
      assert {:ok, _} = AgentRuntime.finish_run(run, %{status: "failed", exit_code: 1})

      assert {:error, :not_active} =
               AgentRuntime.finish_run(run, %{status: "succeeded", exit_code: 0})

      assert AgentRuntime.get_run(run.id).status == "failed"
    end

    test "cannot finish with a non-terminal status", %{run: run} do
      assert {:error, %Ecto.Changeset{}} = AgentRuntime.finish_run(run, %{status: "running"})
    end

    test "a finished run frees the task for a new run", %{
      run: run,
      agent: agent,
      task: task,
      owner: owner
    } do
      {:ok, _} = AgentRuntime.finish_run(run, %{status: "stopped"})
      assert {:ok, _} = AgentRuntime.request_run(agent, task, owner.id)
    end

    test "append_log keeps only the tail", %{run: run} do
      chunk = Enum.map_join(1..500, "\n", &"line #{&1}")
      assert {:ok, updated} = AgentRuntime.append_log(run, chunk)
      lines = String.split(updated.log_tail, "\n")
      assert length(lines) <= 201
      assert List.last(lines) == "line 500"
    end

    test "runtime_env carries the decrypted key and run identity", %{
      run: run,
      agent: agent,
      project: project
    } do
      config = AgentRuntime.get_config(agent.id)
      env = AgentRuntime.runtime_env(run, config, "kaska_pat_x", project.slug)

      assert env["LLM_API_KEY"] == "sk-secret-value"
      assert env["KASKA_PAT"] == "kaska_pat_x"
      assert env["TASK_ID"] == run.task_id
      assert env["PROJECT_SLUG"] == project.slug
      assert env["LLM_PROVIDER_KIND"] == "openai_compatible"
      assert %AgentConfig{} = config
    end
  end
end
