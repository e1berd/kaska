defmodule Kaska.AgentRuntimeFixtures do
  @moduledoc "Board, code-capable agent and pending run fixtures for agent runtime tests."

  alias Kaska.{Accounts, Agents, AgentRuntime, Projects}

  def board_with_code_agent do
    email = "owner#{System.unique_integer([:positive])}@example.com"
    {:ok, owner} = Accounts.register_user(%{email: email, password: "correct horse battery"})

    {:ok, project} =
      Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    {:ok, agent} = Agents.create_agent(owner.id, %{display_name: "Coder"})
    {:ok, _} = Agents.assign_to_project(agent, project.id)

    {:ok, _config} =
      AgentRuntime.upsert_config(agent, %{
        provider_preset: "deepseek",
        model: "deepseek-chat",
        api_key: "sk-secret-value"
      })

    {_p, [todo | _], _t} = Projects.board_snapshot(project.id)

    {:ok, task} =
      Projects.create_task(project.id, todo.id, %{title: "T", assignee_id: agent.id}, owner.id)

    {:ok, run} = AgentRuntime.request_run(agent, task, owner.id)

    %{owner: owner, project: project, agent: agent, task: task, run: run}
  end
end
