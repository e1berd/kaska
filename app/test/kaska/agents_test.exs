defmodule Kaska.AgentsTest do
  use Kaska.DataCase, async: true

  alias Kaska.{Accounts, Agents, Projects}

  defp owner_fixture do
    email = "owner#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  defp project_fixture(owner) do
    {:ok, project} =
      Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    project
  end

  test "create_agent makes a project-less bot owned by the user" do
    owner = owner_fixture()

    assert {:ok, agent} = Agents.create_agent(owner.id, %{display_name: "Coder"})
    assert agent.is_agent
    assert agent.agent_owner_id == owner.id
    assert Agents.agent_projects(agent.id) == []
  end

  test "create_agent rejects a blank name" do
    owner = owner_fixture()
    assert {:error, changeset} = Agents.create_agent(owner.id, %{display_name: ""})
    assert %{display_name: _} = errors_on(changeset)
  end

  test "list_for_owner returns only that owner's agents" do
    owner = owner_fixture()
    other = owner_fixture()
    {:ok, mine} = Agents.create_agent(owner.id, %{display_name: "Mine"})
    {:ok, _theirs} = Agents.create_agent(other.id, %{display_name: "Theirs"})

    assert [listed] = Agents.list_for_owner(owner.id)
    assert listed.id == mine.id
    assert Agents.get_owned_agent(other.id, mine.id) == nil
    assert Agents.get_owned_agent(owner.id, "not-a-uuid") == nil
  end

  test "assigning to projects makes the agent a member that can author comments" do
    owner = owner_fixture()
    project = project_fixture(owner)
    {:ok, agent} = Agents.create_agent(owner.id, %{display_name: "Coder"})

    {:ok, _} = Agents.assign_to_project(agent, project.id)
    assert Projects.member?(project.id, agent.id)
    assert [listed] = Agents.list_agents(project.id)
    assert listed.id == agent.id

    {_p, [todo | _], _t} = Projects.board_snapshot(project.id)
    {:ok, task} = Projects.create_task(project.id, todo.id, %{title: "T"}, owner.id)
    {:ok, comment} = Projects.create_task_comment(project.id, task.id, %{body: "on it"}, agent.id)
    assert comment.author.display_name == "Coder"

    assert :ok = Agents.unassign_from_project(agent, project.id)
    refute Projects.member?(project.id, agent.id)
  end

  test "delete_agent unjoins all projects and removes the user" do
    owner = owner_fixture()
    project = project_fixture(owner)
    {:ok, agent} = Agents.create_agent(owner.id, %{display_name: "Temp"})
    {:ok, _} = Agents.assign_to_project(agent, project.id)

    assert :ok = Agents.delete_agent(agent)
    refute Projects.member?(project.id, agent.id)
    assert Agents.list_for_owner(owner.id) == []
  end
end
