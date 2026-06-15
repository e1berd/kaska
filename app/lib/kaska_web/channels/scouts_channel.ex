defmodule KaskaWeb.ScoutsChannel do
  @moduledoc """
  `scouts:user:<user_id>` — a user managing their own agents ("scouts") across
  projects: callsign, description, role, avatar, project assignments and tokens.
  Only the owner may join their own topic.
  """

  use Phoenix.Channel

  alias Kaska.{Agents, Attachments, Projects, Repo}
  alias Kaska.Accounts.User
  alias Kaska.Attachments.Attachment

  @impl true
  def join("scouts:user:" <> user_id, _payload, socket) do
    case socket.assigns[:current_user] do
      %{id: ^user_id} = user ->
        {:ok, %{scouts: scouts_view(user.id)}, assign(socket, :owner_id, user.id)}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("list_scouts", _payload, socket) do
    {:reply, {:ok, %{scouts: scouts_view(socket.assigns.owner_id)}}, socket}
  end

  def handle_in("list_projects", _payload, socket) do
    projects = Projects.list_projects(socket.assigns.owner_id)
    {:reply, {:ok, %{projects: Enum.map(projects, &project_brief/1)}}, socket}
  end

  def handle_in("create_scout", payload, socket) do
    attrs = take_present(payload, ["display_name", "agent_role", "agent_description"])

    case Agents.create_owned_agent(socket.assigns.owner_id, attrs) do
      {:ok, %{agent: agent, token: token}} ->
        {:reply, {:ok, %{scout: scout_view(agent), token: token}}, socket}

      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}
    end
  end

  def handle_in("update_scout", %{"id" => id} = payload, socket) do
    attrs = take_present(payload, ["display_name", "agent_role", "agent_description"])

    with_scout(socket, id, fn agent ->
      case Agents.update_agent(agent, attrs) do
        {:ok, updated} ->
          {:reply, {:ok, %{scout: scout_view(updated)}}, socket}

        {:error, %Ecto.Changeset{} = cs} ->
          {:reply, {:error, %{errors: format_errors(cs)}}, socket}
      end
    end)
  end

  def handle_in("delete_scout", %{"id" => id}, socket) do
    with_scout(socket, id, fn agent ->
      :ok = Agents.delete_agent(agent)
      {:reply, {:ok, %{id: id}}, socket}
    end)
  end

  def handle_in("regenerate_token", %{"id" => id}, socket) do
    with_scout(socket, id, fn agent ->
      {:ok, token} = Agents.regenerate_token(agent)
      {:reply, {:ok, %{id: id, token: token}}, socket}
    end)
  end

  def handle_in("assign_project", %{"id" => id, "project_id" => project_id}, socket) do
    with_scout(socket, id, fn agent ->
      if Projects.owner?(Projects.get_project(project_id), socket.assigns.owner_id) do
        {:ok, _} = Agents.assign_to_project(agent, project_id)
        {:reply, {:ok, %{scout: scout_view(agent)}}, socket}
      else
        {:reply, {:error, %{message: "forbidden"}}, socket}
      end
    end)
  end

  def handle_in("unassign_project", %{"id" => id, "project_id" => project_id}, socket) do
    with_scout(socket, id, fn agent ->
      :ok = Agents.unassign_from_project(agent, project_id)
      {:reply, {:ok, %{scout: scout_view(reload(agent))}}, socket}
    end)
  end

  def handle_in("request_scout_avatar_upload", %{"id" => id} = payload, socket) do
    with_scout(socket, id, fn agent ->
      attrs = %{
        filename: Map.get(payload, "filename"),
        mime: Map.get(payload, "mime"),
        size: Map.get(payload, "size")
      }

      case Attachments.request_upload("user", agent.id, attrs, socket.assigns.owner_id) do
        {:ok, %{attachment: attachment, put_url: url}} ->
          {:reply,
           {:ok,
            %{attachment_id: attachment.id, put_url: url, storage_key: attachment.storage_key}},
           socket}

        {:error, %Ecto.Changeset{} = cs} ->
          {:reply, {:error, %{errors: format_errors(cs)}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{message: to_string(reason)}}, socket}
      end
    end)
  end

  def handle_in("confirm_scout_avatar_upload", %{"id" => id, "attachment_id" => att_id}, socket) do
    with_scout(socket, id, fn agent ->
      with {:ok, %Attachment{} = attachment} <-
             Attachments.confirm_upload(att_id, socket.assigns.owner_id),
           true <- attachment.parent_type == "user" and attachment.parent_id == agent.id,
           old_key = agent.avatar_key,
           {:ok, updated} <- Agents.update_agent(agent, %{avatar_key: attachment.storage_key}) do
        if old_key && old_key != attachment.storage_key,
          do: Kaska.Storage.delete_object(old_key)

        {:reply, {:ok, %{scout: scout_view(updated)}}, socket}
      else
        false -> {:reply, {:error, %{message: "forbidden"}}, socket}
        {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
      end
    end)
  end

  defp with_scout(socket, id, fun) do
    case Agents.get_owned_agent(socket.assigns.owner_id, id) do
      nil -> {:reply, {:error, %{message: "scout_not_found"}}, socket}
      agent -> fun.(agent)
    end
  end

  defp reload(%User{id: id}), do: Repo.get(User, id)

  defp scouts_view(owner_id) do
    owner_id |> Agents.list_for_owner() |> Enum.map(&scout_view/1)
  end

  defp scout_view(%User{} = u) do
    %{
      id: u.id,
      display_name: u.display_name,
      email: u.email,
      avatar_url: avatar_url(u),
      agent_role: u.agent_role,
      agent_description: u.agent_description,
      projects: u.id |> Agents.agent_projects() |> Enum.map(&project_brief/1),
      inserted_at: u.inserted_at
    }
  end

  defp project_brief(%Projects.Project{} = p) do
    %{id: p.id, slug: p.slug, name: p.name}
  end

  defp avatar_url(%User{avatar_key: nil}), do: nil

  defp avatar_url(%User{avatar_key: key}) do
    case Kaska.Storage.presigned_get(key, expires_in: 3600 * 6) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp take_present(map, keys) do
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
