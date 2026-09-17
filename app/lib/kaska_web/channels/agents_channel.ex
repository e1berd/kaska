defmodule KaskaWeb.AgentsChannel do
  @moduledoc """
  `agents:user:<user_id>` — a user managing their own agents: name, avatar,
  provider settings, project assignments and run history. Only the owner may
  join. Run status changes of the owner's agents are pushed as
  `agent_run_updated`.
  """

  use Phoenix.Channel

  alias Kaska.{Agents, AgentRuntime, Attachments, Projects, Repo}
  alias Kaska.Accounts.User
  alias Kaska.AgentRuntime.{AgentRun, Dispatcher}
  alias Kaska.Attachments.Attachment
  alias KaskaWeb.{AgentViews, BoardChannel}

  @profile_fields ["display_name"]
  @config_fields [
    "provider_preset",
    "auth_method",
    "base_url",
    "model",
    "api_key",
    "system_prompt"
  ]

  @impl true
  def join("agents:user:" <> user_id, _payload, socket) do
    case socket.assigns[:current_user] do
      %{id: ^user_id} = user ->
        :ok = Phoenix.PubSub.subscribe(Kaska.PubSub, AgentRuntime.owner_runs_topic(user.id))

        {:ok,
         %{
           agents: agents_view(user.id),
           presets: AgentViews.presets(),
           limits: AgentViews.limits(),
           active_runs: AgentRuntime.count_active_runs_for_owner(user.id)
         }, assign(socket, :owner_id, user.id)}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info({:agent_run_updated, %AgentRun{} = run}, socket) do
    push(socket, "agent_run_updated", %{
      run: run_with_task(run),
      active_runs: AgentRuntime.count_active_runs_for_owner(socket.assigns.owner_id)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("list_projects", _payload, socket) do
    projects = Projects.list_projects(socket.assigns.owner_id)
    {:reply, {:ok, %{projects: Enum.map(projects, &project_brief/1)}}, socket}
  end

  def handle_in("create_agent", payload, socket) do
    result =
      Repo.transaction(fn ->
        with {:ok, agent} <-
               Agents.create_agent(socket.assigns.owner_id, take(payload, @profile_fields)),
             {:ok, _config} <- AgentRuntime.upsert_config(agent, take(payload, @config_fields)) do
          agent
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, agent} -> {:reply, {:ok, %{agent: agent_view(agent)}}, socket}
      {:error, %Ecto.Changeset{} = cs} -> {:reply, {:error, %{errors: format_errors(cs)}}, socket}
    end
  end

  def handle_in("update_agent", %{"id" => id} = payload, socket) do
    with_agent(socket, id, fn agent ->
      result =
        Repo.transaction(fn ->
          with {:ok, updated} <- Agents.update_agent(agent, take(payload, @profile_fields)),
               {:ok, _config} <-
                 AgentRuntime.upsert_config(updated, take(payload, @config_fields)) do
            updated
          else
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, updated} ->
          broadcast_board_users(updated)
          {:reply, {:ok, %{agent: agent_view(updated)}}, socket}

        {:error, %Ecto.Changeset{} = cs} ->
          {:reply, {:error, %{errors: format_errors(cs)}}, socket}
      end
    end)
  end

  def handle_in("delete_agent", %{"id" => id}, socket) do
    with_agent(socket, id, fn agent ->
      projects = Agents.agent_projects(agent.id)

      Enum.each(AgentRuntime.active_runs_for_agent(agent.id), &stop_before_delete/1)

      :ok = Agents.delete_agent(agent)
      Enum.each(projects, &BoardChannel.broadcast_users/1)
      {:reply, {:ok, %{id: id}}, socket}
    end)
  end

  def handle_in("assign_project", %{"id" => id, "project_id" => project_id}, socket) do
    with_agent(socket, id, fn agent ->
      case Projects.get_project(project_id) do
        %Projects.Project{} = project ->
          if Projects.owner?(project, socket.assigns.owner_id) do
            {:ok, _} = Agents.assign_to_project(agent, project.id)
            BoardChannel.broadcast_users(project)
            {:reply, {:ok, %{agent: agent_view(agent)}}, socket}
          else
            {:reply, {:error, %{message: "forbidden"}}, socket}
          end

        nil ->
          {:reply, {:error, %{message: "project_not_found"}}, socket}
      end
    end)
  end

  def handle_in("unassign_project", %{"id" => id, "project_id" => project_id}, socket) do
    with_agent(socket, id, fn agent ->
      :ok = Agents.unassign_from_project(agent, project_id)

      if project = Projects.get_project(project_id) do
        BoardChannel.broadcast_users(project)
      end

      {:reply, {:ok, %{agent: agent_view(agent)}}, socket}
    end)
  end

  def handle_in("list_runs", %{"id" => id}, socket) do
    with_agent(socket, id, fn agent ->
      runs = agent.id |> AgentRuntime.list_runs_for_agent(50) |> Enum.map(&run_with_task/1)
      {:reply, {:ok, %{runs: runs}}, socket}
    end)
  end

  def handle_in("request_avatar_upload", %{"id" => id} = payload, socket) do
    with_agent(socket, id, fn agent ->
      attrs = %{
        filename: Map.get(payload, "filename"),
        mime: Map.get(payload, "mime"),
        size: Map.get(payload, "size")
      }

      case Attachments.request_upload("user", agent.id, attrs, socket.assigns.owner_id) do
        {:ok, %{attachment: attachment, put_url: url}} ->
          {:reply, {:ok, %{attachment_id: attachment.id, put_url: url}}, socket}

        {:error, %Ecto.Changeset{} = cs} ->
          {:reply, {:error, %{errors: format_errors(cs)}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{message: to_string(reason)}}, socket}
      end
    end)
  end

  def handle_in("confirm_avatar_upload", %{"id" => id, "attachment_id" => att_id}, socket) do
    with_agent(socket, id, fn agent ->
      with {:ok, %Attachment{} = attachment} <-
             Attachments.confirm_upload(att_id, socket.assigns.owner_id),
           true <- attachment.parent_type == "user" and attachment.parent_id == agent.id,
           old_key = agent.avatar_key,
           {:ok, updated} <- Agents.update_agent(agent, %{avatar_key: attachment.storage_key}) do
        if old_key && old_key != attachment.storage_key,
          do: Kaska.Storage.delete_object(old_key)

        broadcast_board_users(updated)
        {:reply, {:ok, %{agent: agent_view(updated)}}, socket}
      else
        false -> {:reply, {:error, %{message: "forbidden"}}, socket}
        {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
      end
    end)
  end

  defp stop_before_delete(run) do
    case Dispatcher.stop(run) do
      {:ok, _} -> :ok
      {:error, :not_active} -> :ok
    end
  end

  defp with_agent(socket, id, fun) do
    case Agents.get_owned_agent(socket.assigns.owner_id, id) do
      nil -> {:reply, {:error, %{message: "agent_not_found"}}, socket}
      agent -> fun.(agent)
    end
  end

  defp broadcast_board_users(%User{id: agent_id}) do
    agent_id |> Agents.agent_projects() |> Enum.each(&BoardChannel.broadcast_users/1)
  end

  defp agents_view(owner_id) do
    owner_id |> Agents.list_for_owner() |> Enum.map(&agent_view/1)
  end

  defp agent_view(%User{} = agent) do
    %{
      id: agent.id,
      display_name: agent.display_name,
      avatar_url: avatar_url(agent),
      config: AgentViews.config(agent),
      projects: agent.id |> Agents.agent_projects() |> Enum.map(&project_brief/1),
      active_runs: agent.id |> AgentRuntime.active_runs_for_agent() |> Enum.map(&run_with_task/1),
      inserted_at: agent.inserted_at
    }
  end

  defp run_with_task(%AgentRun{} = run) do
    task = run.task_id && Projects.get_task(run.task_id)
    project = Projects.get_project(run.project_id)

    run
    |> AgentViews.run()
    |> Map.merge(%{
      task_title: task && task.title,
      project_slug: project && project.slug,
      project_name: project && project.name
    })
  end

  defp project_brief(%Projects.Project{} = p), do: %{id: p.id, slug: p.slug, name: p.name}

  defp avatar_url(%User{avatar_key: nil}), do: nil

  defp avatar_url(%User{avatar_key: key}) do
    case Kaska.Storage.presigned_get(key, expires_in: 3600 * 6) do
      {:ok, url} -> url
      {:error, _} -> nil
    end
  end

  defp take(map, keys) do
    for k <- keys, Map.has_key?(map, k), into: %{}, do: {String.to_existing_atom(k), map[k]}
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
