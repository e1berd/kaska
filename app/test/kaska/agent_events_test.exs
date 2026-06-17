defmodule Kaska.AgentEventsTest do
  use Kaska.DataCase, async: true

  alias Kaska.{Accounts, AgentEvents, Agents, Projects}

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

  defp agent_fixture(owner, project) do
    {:ok, %{agent: agent}} =
      Agents.create_agent(owner.id, project.id, %{display_name: "Scout"})

    agent
  end

  defp task_fixture(project, assignee_id \\ nil) do
    {_p, [todo | _], _t} = Projects.board_snapshot(project.id)

    {:ok, task} =
      Projects.create_task(
        project.id,
        todo.id,
        %{title: "T", assignee_id: assignee_id},
        project.owner_id
      )

    task
  end

  describe "emit/1" do
    test "inserts an event and broadcasts via PubSub" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)

      Phoenix.PubSub.subscribe(Kaska.PubSub, AgentEvents.topic_for(agent.id))

      assert {:ok, event} =
               AgentEvents.emit(%{
                 event_type: "comment_reply",
                 project_id: project.id,
                 agent_id: agent.id,
                 payload: %{"reply_by_id" => owner.id}
               })

      assert event.event_type == "comment_reply"
      assert event.agent_id == agent.id
      assert_receive {:agent_event_new, ^event}
    end
  end

  describe "pending_events/2" do
    test "returns unacked events for the agent" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)

      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{}
        })

      assert [pending] = AgentEvents.pending_events(agent.id)
      assert pending.id == event.id
    end

    test "excludes acked events" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)

      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{}
        })

      {:ok, :acked} = AgentEvents.ack_event(agent.id, event.id)

      assert AgentEvents.pending_events(agent.id) == []
    end

    test "does not return events for other agents" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent1 = agent_fixture(owner, project)

      {:ok, %{agent: agent2}} =
        Agents.create_agent(owner.id, project.id, %{display_name: "Ranger"})

      {:ok, _} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent1.id,
          payload: %{}
        })

      assert AgentEvents.pending_events(agent2.id) == []
    end
  end

  describe "ack_event/2" do
    test "acks a single event by id" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)

      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "comment_reply",
          project_id: project.id,
          agent_id: agent.id,
          payload: %{}
        })

      assert {:ok, :acked} = AgentEvents.ack_event(agent.id, event.id)
      assert AgentEvents.pending_events(agent.id) == []
    end

    test "returns error for unknown event id" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)

      assert {:error, :not_found} = AgentEvents.ack_event(agent.id, Ecto.UUID.generate())
    end

    test "does not ack events belonging to other agents" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent1 = agent_fixture(owner, project)

      {:ok, %{agent: agent2}} =
        Agents.create_agent(owner.id, project.id, %{display_name: "Ranger"})

      {:ok, event} =
        AgentEvents.emit(%{
          event_type: "task_comment",
          project_id: project.id,
          agent_id: agent1.id,
          payload: %{}
        })

      assert {:error, :not_found} = AgentEvents.ack_event(agent2.id, event.id)
      assert [_] = AgentEvents.pending_events(agent1.id)
    end
  end

  describe "notify_on_comment_created/2" do
    test "emits comment_reply when replying to an agent's comment" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)
      task = task_fixture(project)

      Phoenix.PubSub.subscribe(Kaska.PubSub, AgentEvents.topic_for(agent.id))

      {:ok, agent_comment} =
        Projects.create_task_comment(project.id, task.id, %{body: "I'm on it"}, agent.id)

      {:ok, _reply} =
        Projects.create_task_comment(
          project.id,
          task.id,
          %{body: "Thanks!", parent_id: agent_comment.id},
          owner.id
        )

      assert_receive {:agent_event_new, event}
      assert event.event_type == "comment_reply"
      assert event.agent_id == agent.id
      assert event.payload[:reply_by_id] == owner.id
    end

    test "does not emit self-notify when agent replies to own comment" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)
      task = task_fixture(project)

      Phoenix.PubSub.subscribe(Kaska.PubSub, AgentEvents.topic_for(agent.id))

      {:ok, agent_comment} =
        Projects.create_task_comment(project.id, task.id, %{body: "I'm on it"}, agent.id)

      {:ok, _} =
        Projects.create_task_comment(
          project.id,
          task.id,
          %{body: "Self-reply", parent_id: agent_comment.id},
          agent.id
        )

      refute_receive {:agent_event_new, _}, 100
    end

    test "emits task_comment when commenting on a task assigned to an agent" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)
      task = task_fixture(project, agent.id)

      Phoenix.PubSub.subscribe(Kaska.PubSub, AgentEvents.topic_for(agent.id))

      {:ok, _} =
        Projects.create_task_comment(project.id, task.id, %{body: "Any update?"}, owner.id)

      assert_receive {:agent_event_new, event}
      assert event.event_type == "task_comment"
      assert event.agent_id == agent.id
    end

    test "emits comment_mention when body contains @AgentName" do
      owner = owner_fixture()
      project = project_fixture(owner)
      agent = agent_fixture(owner, project)
      task = task_fixture(project)

      Phoenix.PubSub.subscribe(Kaska.PubSub, AgentEvents.topic_for(agent.id))

      {:ok, _} =
        Projects.create_task_comment(
          project.id,
          task.id,
          %{body: "Hey @Scout, can you check this?"},
          owner.id
        )

      assert_receive {:agent_event_new, event}
      assert event.event_type == "comment_mention"
      assert event.agent_id == agent.id
    end
  end
end
