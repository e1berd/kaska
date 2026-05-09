defmodule HardhatWeb.ProjectsChannel do
  @moduledoc """
  `projects:lobby` — public listing + authed creation, edits and media uploads.

  Mutations broadcast `project_created` / `project_updated` / `project_deleted`
  events to all subscribers so other clients refresh in realtime.
  """

  use Phoenix.Channel

  alias Hardhat.{Attachments, Projects, Storage}
  alias Hardhat.Attachments.Attachment
  alias Hardhat.Projects.Project

  @impl true
  def join("projects:lobby", _payload, socket) do
    {:ok, %{projects: Enum.map(Projects.list_projects(), &project_view/1)}, socket}
  end

  @impl true
  def handle_in("list_projects", _payload, socket) do
    {:reply, {:ok, %{projects: Enum.map(Projects.list_projects(), &project_view/1)}}, socket}
  end

  def handle_in(_event, _payload, %{assigns: %{current_user: nil}} = socket) do
    {:reply, {:error, %{message: "unauthorized", code: "unauthorized"}}, socket}
  end

  def handle_in("create_project", payload, socket) do
    %{assigns: %{current_user: user}} = socket

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
    with %Project{} = project <- Projects.get_project(id) do
      attrs =
        %{
          name: Map.get(payload, "name"),
          description: normalize_optional(Map.get(payload, "description"))
        }
        |> drop_unset(payload, ["name", "description"])

      case Projects.update_project(project, attrs) do
        {:ok, updated} ->
          view = project_view(updated)
          broadcast!(socket, "project_updated", view)
          HardhatWeb.Endpoint.broadcast("board:#{view.id}", "project_updated", view)
          {:reply, {:ok, view}, socket}

        {:error, changeset} ->
          {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
      end
    else
      _ -> {:reply, {:error, %{message: "project not found"}}, socket}
    end
  end

  def handle_in("delete_project", %{"id" => id}, socket) do
    with %Project{} = project <- Projects.get_project(id),
         {:ok, _} <- Projects.delete_project(project) do
      _ = project.avatar_key && Storage.delete_object(project.avatar_key)
      _ = project.background_key && Storage.delete_object(project.background_key)
      broadcast!(socket, "project_deleted", %{id: project.id})
      {:reply, {:ok, %{id: project.id}}, socket}
    else
      nil -> {:reply, {:error, %{message: "project not found"}}, socket}
      {:error, _} -> {:reply, {:error, %{message: "could not delete project"}}, socket}
    end
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
    %{assigns: %{current_user: user}} = socket
    project_id = Map.get(payload, "project_id")

    with %Project{} = project <- Projects.get_project(project_id),
         attrs <- %{
           filename: Map.get(payload, "filename"),
           mime: Map.get(payload, "mime"),
           size: Map.get(payload, "size")
         },
         :ok <- validate_image_mime(attrs.mime),
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
      nil -> {:reply, {:error, %{message: "project not found"}}, socket}
      {:error, %Ecto.Changeset{} = cs} -> {:reply, {:error, %{errors: format_errors(cs)}}, socket}
      {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  defp confirm_media_upload(socket, payload, kind) do
    %{assigns: %{current_user: user}} = socket
    project_id = Map.get(payload, "project_id")
    attachment_id = Map.get(payload, "attachment_id")

    with %Project{} = project <- Projects.get_project(project_id),
         {:ok, %Attachment{} = attachment} <- Attachments.confirm_upload(attachment_id, user.id),
         true <- attachment.parent_type == "project" and attachment.parent_id == project.id,
         {:ok, updated} <-
           Projects.set_project_media(project, %{key_for(kind) => attachment.storage_key}) do
      view = project_view(updated)
      broadcast!(socket, "project_updated", view)
      {:reply, {:ok, view}, socket}
    else
      false -> {:reply, {:error, %{message: "forbidden"}}, socket}
      nil -> {:reply, {:error, %{message: "project not found"}}, socket}
      {:error, %Ecto.Changeset{} = cs} -> {:reply, {:error, %{errors: format_errors(cs)}}, socket}
      {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  defp clear_media(socket, id, kind) do
    with %Project{} = project <- Projects.get_project(id),
         {:ok, updated} <- Projects.set_project_media(project, %{key_for(kind) => nil}) do
      view = project_view(updated)
      broadcast!(socket, "project_updated", view)
      {:reply, {:ok, view}, socket}
    else
      nil -> {:reply, {:error, %{message: "project not found"}}, socket}
      {:error, _} -> {:reply, {:error, %{message: "could not update project"}}, socket}
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
      owner_id: p.owner_id,
      avatar_url: media_url(p.avatar_key),
      background_url: media_url(p.background_key),
      inserted_at: p.inserted_at,
      updated_at: p.updated_at
    }
  end

  defp media_url(nil), do: nil

  defp media_url(key) when is_binary(key) do
    case Hardhat.Storage.presigned_get(key, expires_in: 3600 * 6) do
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
