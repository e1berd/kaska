defmodule KaskaWeb.ProjectsChannel do
  @moduledoc """
  `projects:user:<user_id>` — a per-user feed of the projects the user owns or
  was invited to.

  Mutations broadcast `project_created` / `project_updated` / `project_deleted`
  to the `projects:user:<id>` topic of every member, so each client only ever
  sees its own projects update in realtime.
  """

  use Phoenix.Channel

  alias Kaska.{Attachments, Projects, Storage}
  alias Kaska.Attachments.Attachment
  alias Kaska.Projects.Project
  alias KaskaWeb.Endpoint

  @impl true
  def join("projects:user:" <> user_id, _payload, socket) do
    case socket.assigns[:current_user] do
      %{id: ^user_id} = user ->
        {:ok, %{projects: Enum.map(Projects.list_projects(user.id), &project_view/1)}, socket}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("list_projects", _payload, %{assigns: %{current_user: user}} = socket) do
    {:reply, {:ok, %{projects: Enum.map(Projects.list_projects(user.id), &project_view/1)}},
     socket}
  end

  def handle_in("accept_invite", %{"token" => token}, %{assigns: %{current_user: user}} = socket) do
    case Projects.accept_project_invite(token, user.id) do
      {:ok, %Project{} = project} ->
        view = project_view(project)
        broadcast!(socket, "project_created", view)
        KaskaWeb.BoardChannel.broadcast_users(project)
        {:reply, {:ok, %{slug: project.slug}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end

  def handle_in("create_project", payload, %{assigns: %{current_user: user}} = socket) do
    attrs = %{
      slug: Map.get(payload, "slug"),
      name: Map.get(payload, "name"),
      description: Map.get(payload, "description")
    }

    case Projects.create_project(user.id, attrs) do
      {:ok, project} ->
        view = project_view(project)
        broadcast!(socket, "project_created", view)
        {:reply, {:ok, view}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  def handle_in("update_project", %{"id" => id} = payload, socket) do
    with_owned_project(socket, id, fn project ->
      attrs =
        %{
          name: Map.get(payload, "name"),
          description: normalize_optional(Map.get(payload, "description")),
          agent_instructions: normalize_optional(Map.get(payload, "agent_instructions"))
        }
        |> drop_unset(payload, ["name", "description", "agent_instructions"])

      case Projects.update_project(project, attrs) do
        {:ok, updated} ->
          view = project_view(updated)
          broadcast_to_members(updated, "project_updated", view)
          Endpoint.broadcast("board:#{view.id}", "project_updated", view)
          {:reply, {:ok, view}, socket}

        {:error, changeset} ->
          {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
      end
    end)
  end

  def handle_in("delete_project", %{"id" => id}, socket) do
    with_owned_project(socket, id, fn project ->
      member_ids = Projects.member_user_ids(project.id)

      case Projects.delete_project(project) do
        {:ok, _} ->
          _ = project.avatar_key && Storage.delete_object(project.avatar_key)
          _ = project.background_key && Storage.delete_object(project.background_key)

          for member_id <- member_ids do
            Endpoint.broadcast("projects:user:#{member_id}", "project_deleted", %{id: project.id})
          end

          {:reply, {:ok, %{id: project.id}}, socket}

        {:error, _} ->
          {:reply, {:error, %{message: "could not delete project"}}, socket}
      end
    end)
  end

  def handle_in("request_project_avatar_upload", payload, socket),
    do: request_media_upload(socket, payload, :avatar)

  def handle_in("request_project_background_upload", payload, socket),
    do: request_media_upload(socket, payload, :background)

  def handle_in("confirm_project_avatar_upload", payload, socket),
    do: confirm_media_upload(socket, payload, :avatar)

  def handle_in("confirm_project_background_upload", payload, socket),
    do: confirm_media_upload(socket, payload, :background)

  def handle_in("clear_project_avatar", %{"id" => id}, socket),
    do: clear_media(socket, id, :avatar)

  def handle_in("clear_project_background", %{"id" => id}, socket),
    do: clear_media(socket, id, :background)

  defp request_media_upload(socket, payload, kind) do
    project_id = Map.get(payload, "project_id")

    with_owned_project(socket, project_id, fn project ->
      %{assigns: %{current_user: user}} = socket

      attrs = %{
        filename: Map.get(payload, "filename"),
        mime: Map.get(payload, "mime"),
        size: Map.get(payload, "size")
      }

      with :ok <- validate_image_mime(attrs.mime),
           {:ok, %{attachment: attachment, put_url: url}} <-
             Attachments.request_upload("project", project.id, attrs, user.id) do
        {:reply,
         {:ok,
          %{
            kind: Atom.to_string(kind),
            attachment_id: attachment.id,
            put_url: url,
            storage_key: attachment.storage_key
          }}, socket}
      else
        {:error, %Ecto.Changeset{} = cs} ->
          {:reply, {:error, %{errors: format_errors(cs)}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{message: to_string(reason)}}, socket}
      end
    end)
  end

  defp confirm_media_upload(socket, payload, kind) do
    project_id = Map.get(payload, "project_id")
    attachment_id = Map.get(payload, "attachment_id")

    with_owned_project(socket, project_id, fn project ->
      %{assigns: %{current_user: user}} = socket

      with {:ok, %Attachment{} = attachment} <- Attachments.confirm_upload(attachment_id, user.id),
           true <- attachment.parent_type == "project" and attachment.parent_id == project.id,
           {:ok, updated} <-
             Projects.set_project_media(project, %{key_for(kind) => attachment.storage_key}) do
        view = project_view(updated)
        broadcast_to_members(updated, "project_updated", view)
        Endpoint.broadcast("board:#{view.id}", "project_updated", view)
        {:reply, {:ok, view}, socket}
      else
        false ->
          {:reply, {:error, %{message: "forbidden"}}, socket}

        {:error, %Ecto.Changeset{} = cs} ->
          {:reply, {:error, %{errors: format_errors(cs)}}, socket}

        {:error, reason} ->
          {:reply, {:error, %{message: to_string(reason)}}, socket}
      end
    end)
  end

  defp clear_media(socket, id, kind) do
    with_owned_project(socket, id, fn project ->
      case Projects.set_project_media(project, %{key_for(kind) => nil}) do
        {:ok, updated} ->
          view = project_view(updated)
          broadcast_to_members(updated, "project_updated", view)
          Endpoint.broadcast("board:#{view.id}", "project_updated", view)
          {:reply, {:ok, view}, socket}

        {:error, _} ->
          {:reply, {:error, %{message: "could not update project"}}, socket}
      end
    end)
  end

  defp with_owned_project(socket, id, fun) do
    user = socket.assigns[:current_user]

    case Projects.get_project(id) do
      %Project{} = project ->
        if user && Projects.owner?(project, user.id) do
          fun.(project)
        else
          {:reply, {:error, %{message: "forbidden", reason: "forbidden"}}, socket}
        end

      nil ->
        {:reply, {:error, %{message: "project not found"}}, socket}
    end
  end

  defp broadcast_to_members(%Project{} = project, event, view) do
    for member_id <- Projects.member_user_ids(project.id) do
      Endpoint.broadcast("projects:user:#{member_id}", event, view)
    end
  end

  defp key_for(:avatar), do: :avatar_key
  defp key_for(:background), do: :background_key

  defp validate_image_mime(mime) when is_binary(mime) do
    if String.starts_with?(mime, "image/"), do: :ok, else: {:error, :only_images_allowed}
  end

  defp validate_image_mime(_), do: {:error, :missing_mime}

  defp project_view(%Project{} = p) do
    %{
      id: p.id,
      slug: p.slug,
      name: p.name,
      description: p.description,
      agent_instructions: p.agent_instructions,
      owner_id: p.owner_id,
      public_link: p.public_link,
      theme_slug: p.theme_slug,
      avatar_url: media_url(p.avatar_key),
      background_url: media_url(p.background_key),
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end

  defp media_url(nil), do: nil

  defp media_url(key) when is_binary(key) do
    case Kaska.Storage.presigned_get(key, expires_in: 3600 * 6) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp normalize_optional(nil), do: nil
  defp normalize_optional(""), do: nil
  defp normalize_optional(value) when is_binary(value), do: value
  defp normalize_optional(_), do: nil

  defp drop_unset(attrs, payload, keys) do
    Enum.reduce(keys, attrs, fn key, acc ->
      if Map.has_key?(payload, key), do: acc, else: Map.delete(acc, String.to_existing_atom(key))
    end)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
