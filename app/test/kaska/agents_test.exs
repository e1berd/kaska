defmodule Kaska.AgentsTest do
  use Kaska.DataCase, async: true

  alias Kaska.{Accounts, Agents, ApiTokens, Projects}

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

  describe "create_agent/3" do
    test "creates a bot member with a token that authenticates as the bot" do
      owner = owner_fixture()
      project = project_fixture(owner)

      assert {:ok, %{agent: agent, token: token}} =
               Agents.create_agent(owner.id, project.id, %{display_name: "Clerk"})

      assert agent.is_agent
      assert agent.display_name == "Clerk"
      assert agent.agent_owner_id == owner.id
      assert String.starts_with?(token, "kaska_pat_")
      assert Projects.member?(project.id, agent.id)

      assert {:ok, resolved} = ApiTokens.verify_token(token)
      assert resolved.id == agent.id
    end

    test "rejects a blank callsign and rolls back" do
      owner = owner_fixture()
      project = project_fixture(owner)

      assert {:error, changeset} = Agents.create_agent(owner.id, project.id, %{display_name: ""})
      assert %{display_name: _} = errors_on(changeset)
      assert Agents.list_agents(project.id) == []
    end
  end

  describe "list/update/remove" do
    setup do
      owner = owner_fixture()
      project = project_fixture(owner)

      {:ok, %{agent: agent, token: token}} =
        Agents.create_agent(owner.id, project.id, %{display_name: "Clerk"})

      %{owner: owner, project: project, agent: agent, token: token}
    end

    test "lists agents of the project", %{project: project, agent: agent} do
      assert [listed] = Agents.list_agents(project.id)
      assert listed.id == agent.id
    end

    test "updates the callsign", %{agent: agent} do
      assert {:ok, updated} = Agents.update_agent(agent, %{display_name: "Ranger"})
      assert updated.display_name == "Ranger"
    end

    test "comments made as the agent carry its identity", %{project: project, agent: agent} do
      {_p, [todo | _], _t} = Projects.board_snapshot(project.id)
      {:ok, task} = Projects.create_task(project.id, todo.id, %{title: "T"}, agent.id)

      {:ok, comment} =
        Projects.create_task_comment(project.id, task.id, %{body: "on it"}, agent.id)

      assert comment.author_id == agent.id
      assert comment.author.display_name == "Clerk"
      assert comment.author.is_agent
    end

    test "remove_agent unjoins and revokes its token", %{
      project: project,
      agent: agent,
      token: token
    } do
      assert :ok = Agents.remove_agent(project.id, agent)
      refute Projects.member?(project.id, agent.id)
      assert :error = ApiTokens.verify_token(token)
      assert Agents.list_agents(project.id) == []
    end

    test "regenerate_token revokes the old token and issues a new one", %{
      agent: agent,
      token: token
    } do
      assert {:ok, fresh} = Agents.regenerate_token(agent)
      assert fresh != token
      assert :error = ApiTokens.verify_token(token)
      assert {:ok, resolved} = ApiTokens.verify_token(fresh)
      assert resolved.id == agent.id
    end
  end

  describe "owner-scoped management" do
    test "create_owned_agent makes a project-less agent with a working token" do
      owner = owner_fixture()

      assert {:ok, %{agent: agent, token: token}} =
               Agents.create_owned_agent(owner.id, %{display_name: "Nomad"})

      assert agent.agent_owner_id == owner.id
      assert Agents.agent_projects(agent.id) == []
      assert {:ok, resolved} = ApiTokens.verify_token(token)
      assert resolved.id == agent.id
    end

    test "list_for_owner returns only that owner's agents" do
      owner = owner_fixture()
      other = owner_fixture()
      {:ok, %{agent: mine}} = Agents.create_owned_agent(owner.id, %{display_name: "Mine"})
      {:ok, %{agent: _theirs}} = Agents.create_owned_agent(other.id, %{display_name: "Theirs"})

      assert [listed] = Agents.list_for_owner(owner.id)
      assert listed.id == mine.id
    end

    test "profile fields (description, role) round-trip" do
      owner = owner_fixture()
      {:ok, %{agent: agent}} = Agents.create_owned_agent(owner.id, %{display_name: "QA"})

      assert {:ok, updated} =
               Agents.update_agent(agent, %{
                 agent_role: "ответственный за качество",
                 agent_description: "Проверяет каждую задачу перед Done."
               })

      assert updated.agent_role == "ответственный за качество"
      assert updated.agent_description == "Проверяет каждую задачу перед Done."
    end

    test "assign to projects and keep token until removed from the last one" do
      owner = owner_fixture()
      p1 = project_fixture(owner)
      p2 = project_fixture(owner)

      {:ok, %{agent: agent, token: token}} =
        Agents.create_owned_agent(owner.id, %{display_name: "Multi"})

      {:ok, _} = Agents.assign_to_project(agent, p1.id)
      {:ok, _} = Agents.assign_to_project(agent, p2.id)

      assert Enum.map(Agents.agent_projects(agent.id), & &1.id) |> Enum.sort() ==
               Enum.sort([p1.id, p2.id])

      :ok = Agents.remove_agent(p1.id, agent)
      assert {:ok, _} = ApiTokens.verify_token(token)

      :ok = Agents.remove_agent(p2.id, agent)
      assert :error = ApiTokens.verify_token(token)
    end

    test "delete_agent retires it from all projects and revokes tokens" do
      owner = owner_fixture()
      p1 = project_fixture(owner)

      {:ok, %{agent: agent, token: token}} =
        Agents.create_owned_agent(owner.id, %{display_name: "Bye"})

      {:ok, _} = Agents.assign_to_project(agent, p1.id)

      assert :ok = Agents.delete_agent(agent)
      assert Agents.agent_projects(agent.id) == []
      assert :error = ApiTokens.verify_token(token)
    end
  end
end
