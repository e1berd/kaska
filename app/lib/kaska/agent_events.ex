defmodule Kaska.AgentEvents do
  @moduledoc """
  Outbox for events that need realtime delivery to agents.

  When a comment is created, the system checks:
  1. Is it a reply to an agent's comment? → emit `comment_reply`
  2. Does it @mention an agent? → emit `comment_mention`
  3. Is the task assigned to an agent? → emit `task_comment`

  Agents consume events via long-poll REST and acknowledge with an ack cursor.
  Long-poll wakes via Phoenix.PubSub on emit, not polling.
  """

  import Ecto.Query

  alias Kaska.{Projects, Repo}
  alias Kaska.AgentEvents.AgentEvent
  alias Kaska.Projects.TaskComment

  @topic "agent_events"

  def topic, do: @topic

  @doc """
  Emits an event to the agent events outbox and notifies via PubSub.
  """
  def emit(attrs) when is_map(attrs) do
    %AgentEvent{}
    |> AgentEvent.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, event} = result ->
        Phoenix.PubSub.broadcast(Kaska.PubSub, @topic, {:agent_event_new, event})
        result

      error ->
        error
    end
  end

  @doc """
  Fetches pending events for an agent, ordered by insertion time.
  Returns events that have not been acked yet.
  """
  def pending_events(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    since = Keyword.get(opts, :since)

    query =
      from e in AgentEvent,
        where: e.agent_id == ^agent_id and is_nil(e.acked_at),
        order_by: [asc: e.inserted_at],
        limit: ^limit

    query =
      if since do
        from e in query, where: e.inserted_at > ^since
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Acknowledges delivery of a specific event. Only acks the single event by id.
  """
  def ack_event(agent_id, event_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(e in AgentEvent,
        where: e.id == ^event_id and e.agent_id == ^agent_id and is_nil(e.acked_at)
      )
      |> Repo.update_all(set: [acked_at: now])

    if count > 0, do: {:ok, :acked}, else: {:error, :not_found}
  end

  @doc """
  When a comment is created, check if any agents should be notified and emit events.
  Runs synchronously to guarantee outbox write succeeds before comment creation returns.
  """
  def notify_on_comment_created(%TaskComment{} = comment, project_id) do
    task = Projects.get_task(comment.task_id)
    author_id = comment.author_id

    # 1. Reply to an agent's comment
    if comment.parent_id do
      case Projects.get_task_comment(comment.parent_id) do
        %TaskComment{author_id: agent_id} when not is_nil(agent_id) ->
          if agent_id != author_id and agent?(agent_id) do
            emit(%{
              event_type: "comment_reply",
              project_id: project_id,
              task_id: comment.task_id,
              comment_id: comment.id,
              agent_id: agent_id,
              payload: %{
                reply_by_id: author_id,
                reply_by_name: comment.author && comment.author.display_name,
                parent_comment_id: comment.parent_id
              }
            })
          end

        _ ->
          :ok
      end
    end

    # 2. @mention agents in comment body_doc (tiptap mentions) or body (markdown fallback)
    mentioned_agent_ids = extract_mentioned_agent_ids(comment)

    for agent_id <- mentioned_agent_ids, agent_id != author_id do
      emit(%{
        event_type: "comment_mention",
        project_id: project_id,
        task_id: comment.task_id,
        comment_id: comment.id,
        agent_id: agent_id,
        payload: %{
          mentioned_by_id: author_id,
          mentioned_by_name: comment.author && comment.author.display_name
        }
      })
    end

    # 3. Comment on a task assigned to an agent
    if task && task.assignee_id && task.assignee_id != author_id && agent?(task.assignee_id) do
      emit(%{
        event_type: "task_comment",
        project_id: project_id,
        task_id: comment.task_id,
        comment_id: comment.id,
        agent_id: task.assignee_id,
        payload: %{
          commented_by_id: author_id,
          commented_by_name: comment.author && comment.author.display_name
        }
      })
    end

    :ok
  end

  defp agent?(user_id) do
    case Kaska.Accounts.get_user(user_id) do
      %{is_agent: true} -> true
      _ -> false
    end
  end

  defp extract_mentioned_agent_ids(%TaskComment{} = comment) do
    project_agents = Kaska.Agents.list_agents(comment.project_id)

    # Try body_doc first (tiptap mention nodes), fall back to markdown body search
    doc_mentions = mentions_from_doc(comment.body_doc, project_agents)

    if doc_mentions != [] do
      doc_mentions
    else
      mentions_from_body(comment.body || "", project_agents)
    end
  end

  defp mentions_from_doc(%{"content" => content} = _doc, agents) when is_list(content) do
    agent_map = Map.new(agents, fn a -> {a.display_name, a.id} end)

    content
    |> extract_text_from_nodes()
    |> Enum.flat_map(fn text ->
      for {name, id} <- agent_map,
          String.contains?(text, "@#{name}"),
          do: id
    end)
    |> Enum.uniq()
  end

  defp mentions_from_doc(_, _), do: []

  defp extract_text_from_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{"text" => text} when is_binary(text) -> [text]
      %{"content" => children} -> extract_text_from_nodes(children)
      _ -> []
    end)
  end

  defp extract_text_from_nodes(_), do: []

  defp mentions_from_body(body, agents) do
    Enum.filter(agents, fn agent ->
      name = agent.display_name || ""
      String.contains?(body, "@#{name}")
    end)
    |> Enum.map(& &1.id)
  end
end
