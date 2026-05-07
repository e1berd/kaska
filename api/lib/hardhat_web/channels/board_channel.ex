defmodule HardhatWeb.BoardChannel do
  @moduledoc """
  `board:<project_id>` — public read, authed write.

  On join: returns a snapshot of `{project, columns, tasks}` so a fresh client
  (including anonymous guests) can render the board immediately.

  Mutations broadcast deltas (`column_created`, `task_moved`, …) to all
  subscribers of the topic. Clients reconcile their local state from these.
  """

  use Phoenix.Channel

  alias Hardhat.{Attachments, Projects}
  alias HardhatWeb.Presence
  alias Hardhat.Attachments.Attachment
  alias Hardhat.Projects.{Column, Project, Task}

  @impl true
  def join("board:" <> project_id, payload, socket) do
    join_with_snapshot(Projects.board_snapshot(project_id), payload, socket)
  end

  def join("board_slug:" <> slug, payload, socket) do
    case Projects.get_project_by_slug(slug) do
      nil -> {:error, %{reason: "not_found"}}
      project -> join_with_snapshot(Projects.board_snapshot(project.id), payload, socket)
    end
  end

  defp join_with_snapshot(nil, _payload, _socket), do: {:error, %{reason: "not_found"}}

  defp join_with_snapshot({project, columns, tasks}, _payload, socket) do
    socket = assign(socket, :project_id, project.id)
    send(self(), :after_join_presence)
    task_ids = Enum.map(tasks, & &1.id)
    task_types = Projects.list_task_types(project.id)
    users = Hardhat.Accounts.list_users()

    attachments =
      for t_id <- task_ids,
          a <- Attachments.list_for("task", t_id) do
        attachment_view(a)
      end

    {:ok,
     %{
       project: project_view(project),
       columns: Enum.map(columns, &column_view/1),
       tasks: Enum.map(tasks, &task_view/1),
       task_types: Enum.map(task_types, &task_type_view/1),
       users: Enum.map(users, &user_view/1),
       attachments: attachments
     }, socket}
  end

  @impl true
  def handle_info(:after_join_presence, socket) do
    if user = socket.assigns[:current_user] do
      {:ok, _} =
        Presence.track(socket, user.id, %{
          online_at: inspect(System.system_time(:second))
        })
    end

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  ## Authorization gate ──────────────────────────────────────────────────

  @impl true
  def handle_in(_event, _payload, %{assigns: %{current_user: nil}} = socket) do
    {:reply, {:error, %{message: "unauthorized", code: "unauthorized"}}, socket}
  end

  ## Columns ─────────────────────────────────────────────────────────────

  def handle_in("create_column", payload, socket) do
    project_id = socket.assigns.project_id
    name = Map.get(payload, "name")

    case Projects.create_column(project_id, %{name: name}) do
      {:ok, column} ->
        view = column_view(column)
        broadcast!(socket, "column_created", view)
        {:reply, {:ok, view}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  def handle_in("rename_column", %{"id" => id} = payload, socket) do
    with %Column{} = column <- get_owned_column(id, socket),
         {:ok, column} <- Projects.rename_column(column, %{name: Map.get(payload, "name")}) do
      view = column_view(column)
      broadcast!(socket, "column_updated", view)
      {:reply, {:ok, view}, socket}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}

      _ ->
        {:reply, {:error, %{message: "column_not_found"}}, socket}
    end
  end

  def handle_in("delete_column", %{"id" => id}, socket) do
    with %Column{} = column <- get_owned_column(id, socket),
         {:ok, _} <- Projects.delete_column(column) do
      broadcast!(socket, "column_deleted", %{id: id})
      {:reply, {:ok, %{id: id}}, socket}
    else
      _ -> {:reply, {:error, %{message: "column_not_found"}}, socket}
    end
  end

  def handle_in("move_column", %{"id" => id} = payload, socket) do
    with %Column{} = column <- get_owned_column(id, socket),
         {:ok, column} <-
           Projects.move_column(column, payload["before_id"], payload["after_id"]) do
      view = column_view(column)
      broadcast!(socket, "column_moved", view)
      {:reply, {:ok, view}, socket}
    else
      {:error, reason} when is_atom(reason) ->
        {:reply, {:error, %{message: to_string(reason)}}, socket}

      _ ->
        {:reply, {:error, %{message: "column_not_found"}}, socket}
    end
  end

  ## Task Types ─────────────────────────────────────────────────────────

  def handle_in("create_task_type", payload, socket) do
    project_id = socket.assigns.project_id

    attrs = %{
      name: Map.get(payload, "name"),
      description: Map.get(payload, "description"),
      color: Map.get(payload, "color") || "gray",
      project_id: project_id
    }

    case Projects.create_task_type(attrs) do
      {:ok, task_type} ->
        view = task_type_view(task_type)
        broadcast!(socket, "task_type_created", view)
        {:reply, {:ok, view}, socket}

      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}
    end
  end

  def handle_in("update_task_type", %{"id" => id} = payload, socket) do
    attrs = take_present(payload, ["name", "description", "color"])

    with %Hardhat.Projects.TaskType{} = task_type <- get_owned_task_type(id, socket),
         {:ok, task_type} <- Projects.update_task_type(task_type, attrs) do
      view = task_type_view(task_type)
      broadcast!(socket, "task_type_updated", view)
      {:reply, {:ok, view}, socket}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}

      _ ->
        {:reply, {:error, %{message: "task_type_not_found"}}, socket}
    end
  end

  def handle_in("delete_task_type", %{"id" => id}, socket) do
    with %Hardhat.Projects.TaskType{} = task_type <- get_owned_task_type(id, socket),
         {:ok, _} <- Projects.delete_task_type(task_type) do
      broadcast!(socket, "task_type_deleted", %{id: id})
      {:reply, :ok, socket}
    else
      _ -> {:reply, {:error, %{message: "task_type_not_found"}}, socket}
    end
  end

  ## Tasks ───────────────────────────────────────────────────────────────

  def handle_in("create_task", %{"column_id" => column_id} = payload, socket) do
    project_id = socket.assigns.project_id
    creator_id = socket.assigns.current_user.id

    attrs = %{
      title: Map.get(payload, "title"),
      description: Map.get(payload, "description"),
      start_date: Map.get(payload, "start_date"),
      end_date: Map.get(payload, "end_date"),
      assignee_id: Map.get(payload, "assignee_id"),
      task_type_id: Map.get(payload, "task_type_id")
    }

    case Projects.create_task(project_id, column_id, attrs, creator_id) do
      {:ok, task} ->
        view = task_view(task)
        broadcast!(socket, "task_created", view)
        {:reply, {:ok, view}, socket}

      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  def handle_in("update_task", %{"id" => id} = payload, socket) do
    attrs =
      take_present(payload, [
        "title",
        "body_doc",
        "start_date",
        "end_date",
        "assignee_id",
        "task_type_id"
      ])

    with %Task{} = task <- get_owned_task(id, socket),
         {:ok, task} <- Projects.update_task(task, attrs) do
      view = task_view(task)
      broadcast!(socket, "task_updated", view)
      {:reply, {:ok, view}, socket}
    else
      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}

      _ ->
        {:reply, {:error, %{message: "task_not_found"}}, socket}
    end
  end

  def handle_in("delete_task", %{"id" => id}, socket) do
    with %Task{} = task <- get_owned_task(id, socket),
         {:ok, _} <- Projects.delete_task(task) do
      actor = socket.assigns.current_user

      payload = %{
        id: id,
        title: task.title,
        deleted_by_id: actor.id,
        deleted_by_display_name: actor.display_name,
        deleted_by_email: actor.email
      }

      broadcast!(socket, "task_deleted", payload)
      {:reply, {:ok, payload}, socket}
    else
      _ -> {:reply, {:error, %{message: "task_not_found"}}, socket}
    end
  end

  def handle_in("move_task", %{"id" => id, "column_id" => column_id} = payload, socket) do
    with %Task{} = task <- get_owned_task(id, socket),
         {:ok, task} <-
           Projects.move_task(
             task,
             column_id,
             payload["before_id"],
             payload["after_id"]
           ) do
      view = task_view(task)
      broadcast!(socket, "task_moved", view)
      {:reply, {:ok, view}, socket}
    else
      {:error, reason} when is_atom(reason) ->
        {:reply, {:error, %{message: to_string(reason)}}, socket}

      _ ->
        {:reply, {:error, %{message: "task_not_found"}}, socket}
    end
  end

  ## Attachments ─────────────────────────────────────────────────────────

  def handle_in("request_task_attachment_upload", %{"task_id" => task_id} = payload, socket) do
    with %Task{} = task <- get_owned_task(task_id, socket),
         attrs = %{
           filename: Map.get(payload, "filename"),
           mime: Map.get(payload, "mime"),
           size: Map.get(payload, "size")
         },
         {:ok, %{attachment: attachment, put_url: put_url}} <-
           Attachments.request_upload("task", task.id, attrs, socket.assigns.current_user.id) do
      {:reply,
       {:ok,
        %{
          attachment_id: attachment.id,
          put_url: put_url,
          storage_key: attachment.storage_key,
          mime: attachment.mime
        }}, socket}
    else
      nil -> {:reply, {:error, %{message: "task_not_found"}}, socket}
      {:error, %Ecto.Changeset{} = cs} -> {:reply, {:error, %{errors: format_errors(cs)}}, socket}
      {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  def handle_in("confirm_task_attachment_upload", %{"attachment_id" => id}, socket) do
    user_id = socket.assigns.current_user.id

    case Attachments.confirm_upload(id, user_id) do
      {:ok, %Attachment{parent_type: "task"} = attachment} ->
        # Make sure the attachment really belongs to a task in *this* project.
        case Projects.get_task(attachment.parent_id) do
          %Task{project_id: pid} when pid == socket.assigns.project_id ->
            view = attachment_view(attachment)
            broadcast!(socket, "task_attachment_added", view)
            {:reply, {:ok, view}, socket}

          _ ->
            {:reply, {:error, %{message: "task_not_found"}}, socket}
        end

      {:error, reason} ->
        {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  def handle_in("delete_task_attachment", %{"id" => id}, socket) do
    with %Attachment{parent_type: "task", parent_id: task_id} = attachment <- Attachments.get(id),
         %Task{project_id: pid} <- Projects.get_task(task_id),
         true <- pid == socket.assigns.project_id,
         {:ok, _} <- Attachments.delete_attachment(attachment) do
      broadcast!(socket, "task_attachment_removed", %{id: id, task_id: task_id})
      {:reply, {:ok, %{id: id}}, socket}
    else
      _ -> {:reply, {:error, %{message: "attachment_not_found"}}, socket}
    end
  end

  def handle_in("set_active_task", payload, socket) do
    task_id = Map.get(payload, "task_id")
    editing_description = Map.get(payload, "editing_description", false)

    with true <- is_nil(task_id) or task_belongs_to_project?(task_id, socket),
         user when not is_nil(user) <- socket.assigns[:current_user],
         {:ok, _} <-
           Presence.update(socket, user.id, %{
             online_at: inspect(System.system_time(:second)),
             active_task_id: task_id,
             editing_description: editing_description
           }) do
      {:reply, {:ok, %{task_id: task_id}}, socket}
    else
      false -> {:reply, {:error, %{message: "task_not_found"}}, socket}
      _ -> {:reply, {:error, %{message: "unauthorized"}}, socket}
    end
  end

  ## Helpers ─────────────────────────────────────────────────────────────

  defp get_owned_column(id, socket) do
    case Projects.get_column(id) do
      %Column{project_id: pid} = c when pid == socket.assigns.project_id -> c
      _ -> nil
    end
  end

  defp get_owned_task(id, socket) do
    case Projects.get_task(id) do
      %Task{project_id: pid} = t when pid == socket.assigns.project_id -> t
      _ -> nil
    end
  end

  defp task_belongs_to_project?(id, socket) do
    case Projects.get_task(id) do
      %Task{project_id: pid} -> pid == socket.assigns.project_id
      _ -> false
    end
  end

  defp get_owned_task_type(id, socket) do
    case Projects.get_task_type(id) do
      %Hardhat.Projects.TaskType{project_id: pid} = tt when pid == socket.assigns.project_id -> tt
      _ -> nil
    end
  end

  defp project_view(%Project{} = p) do
    %{
      id: p.id,
      slug: p.slug,
      name: p.name,
      description: p.description,
      owner_id: p.owner_id
    }
  end

  defp column_view(%Column{} = c) do
    %{id: c.id, project_id: c.project_id, name: c.name, rank: c.rank}
  end

  defp task_view(%Task{} = t) do
    %{
      id: t.id,
      project_id: t.project_id,
      column_id: t.column_id,
      title: t.title,
      body_doc: t.body_doc,
      rank: t.rank,
      creator_id: t.creator_id,
      assignee_id: t.assignee_id,
      task_type_id: t.task_type_id,
      start_date: t.start_date,
      end_date: t.end_date,
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  defp task_type_view(%Hardhat.Projects.TaskType{} = tt) do
    %{
      id: tt.id,
      project_id: tt.project_id,
      name: tt.name,
      description: tt.description,
      color: tt.color
    }
  end

  defp user_view(%Hardhat.Accounts.User{} = u) do
    %{
      id: u.id,
      email: u.email,
      role: u.role,
      confirmed_at: u.confirmed_at,
      display_name: u.display_name,
      avatar_url: avatar_url(u)
    }
  end

  defp avatar_url(%{avatar_key: nil}), do: nil

  defp avatar_url(%{avatar_key: key}) when is_binary(key) do
    case Hardhat.Storage.presigned_get(key, expires_in: 3600 * 6) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp avatar_url(_), do: nil

  defp attachment_view(%Attachment{} = a) do
    %{
      id: a.id,
      task_id: a.parent_id,
      kind: a.kind,
      filename: a.filename,
      mime: a.mime,
      size: a.size,
      url: Attachments.view_url(a),
      creator_id: a.creator_id,
      inserted_at: a.inserted_at
    }
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
