defmodule KaskaWeb.BoardChannel do
  @moduledoc """
  `board:<project_id>` — public read, authed write.

  On join: returns a snapshot of `{project, columns, tasks}` so a fresh client
  (including anonymous guests) can render the board immediately.

  Mutations broadcast deltas (`column_created`, `task_moved`, …) to all
  subscribers of the topic. Clients reconcile their local state from these.
  """

  use Phoenix.Channel

  alias Kaska.{Accounts, Attachments, Projects}
  alias Kaska.Accounts.UserNotifier
  alias KaskaWeb.Endpoint
  alias KaskaWeb.Presence
  alias Kaska.Attachments.Attachment
  alias Kaska.Projects.{Column, Project, ProjectInvite, ProjectMember, Task, TaskComment}
  @guest_comment_max_length 255
  @guest_comment_min_interval_ms 4000
  @guest_comment_rate_table :kaska_guest_comment_rate

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
    user = socket.assigns[:current_user]
    user_id = user && user.id

    if Projects.board_accessible?(project, user_id) do
      can_write = is_binary(user_id) and Projects.member?(project.id, user_id)

      socket =
        socket
        |> assign(:project_id, project.id)
        |> assign(:can_write, can_write)

      send(self(), :after_join_presence)
      task_ids = Enum.map(tasks, & &1.id)
      task_types = Projects.list_task_types(project.id)
      task_comments = Projects.list_task_comments(project.id)
      users = Projects.list_member_users(project.id)
      allow_guest_comments = Accounts.get_setting("allow_guest_comments", "false") == "true"

      attachments =
        for t_id <- task_ids,
            a <- Attachments.list_for("task", t_id) do
          attachment_view(a)
        end

      {:ok,
       %{
         project: project_view(project),
         can_write: can_write,
         is_owner: is_binary(user_id) and Projects.owner?(project, user_id),
         my_theme_slug: user_id && Projects.get_user_project_theme(project.id, user_id),
         columns: Enum.map(columns, &column_view/1),
         tasks: Enum.map(tasks, &task_view/1),
         task_types: Enum.map(task_types, &task_type_view/1),
         task_comments: Enum.map(task_comments, &task_comment_view/1),
         settings: %{allow_guest_comments: allow_guest_comments},
         users: Enum.map(users, &user_view/1),
         attachments: attachments
       }, socket}
    else
      {:error, %{reason: "forbidden"}}
    end
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
  def handle_in(event, _payload, %{assigns: %{can_write: false}} = socket)
      when event != "create_task_comment" do
    {:reply, {:error, %{message: "forbidden", code: "forbidden"}}, socket}
  end

  def handle_in("create_task_comment", %{"task_id" => task_id} = payload, socket) do
    body =
      payload
      |> Map.get("body", "")
      |> to_string()
      |> String.trim()

    guest_name = Map.get(payload, "guest_name")
    allow_guest_comments = Accounts.get_setting("allow_guest_comments", "false") == "true"
    actor = socket.assigns[:current_user]

    cond do
      is_nil(actor) and !allow_guest_comments ->
        {:reply, {:error, %{message: "guest_comments_disabled"}}, socket}

      is_nil(actor) and String.length(body) > @guest_comment_max_length ->
        {:reply, {:error, %{message: "guest_comment_too_long"}}, socket}

      is_nil(actor) and match?({:error, :rate_limited}, check_guest_comment_rate(socket, task_id)) ->
        {:reply, {:error, %{message: "guest_comment_rate_limited"}}, socket}

      true ->
        attrs = %{body: body, guest_name: guest_name}
        author_id = if actor, do: actor.id, else: nil

        case Projects.create_task_comment(socket.assigns.project_id, task_id, attrs, author_id) do
          {:ok, comment} ->
            view = task_comment_view(comment)
            broadcast!(socket, "task_comment_created", view)
            {:reply, {:ok, view}, socket}

          {:error, %Ecto.Changeset{} = cs} ->
            {:reply, {:error, %{errors: format_errors(cs)}}, socket}

          {:error, reason} ->
            {:reply, {:error, %{message: to_string(reason)}}, socket}
        end
    end
  end

  def handle_in("delete_task_comment", %{"id" => id}, socket) do
    actor = socket.assigns[:current_user]

    with %TaskComment{} = comment <- get_owned_task_comment(id, socket),
         true <- can_delete_comment?(comment, actor),
         {:ok, _} <- Projects.delete_task_comment(comment) do
      payload = %{id: id, task_id: comment.task_id}
      broadcast!(socket, "task_comment_deleted", payload)
      {:reply, {:ok, payload}, socket}
    else
      nil -> {:reply, {:error, %{message: "task_comment_not_found"}}, socket}
      false -> {:reply, {:error, %{message: "forbidden"}}, socket}
      {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
      _ -> {:reply, {:error, %{message: "task_comment_not_found"}}, socket}
    end
  end

  ## Members ─────────────────────────────────────────────────────────────

  def handle_in("list_members", _payload, socket) do
    members = Projects.list_members(socket.assigns.project_id)
    {:reply, {:ok, %{members: Enum.map(members, &member_view/1)}}, socket}
  end

  def handle_in("list_invites", _payload, socket) do
    with_owned_project(socket, fn project ->
      invites = Projects.list_project_invites(project.id)
      {:reply, {:ok, %{invites: Enum.map(invites, &invite_view/1)}}, socket}
    end)
  end

  def handle_in("invite_member", payload, socket) do
    with_owned_project(socket, fn project ->
      email = normalize_invite_email(Map.get(payload, "email"))
      expires_in_minutes = Map.get(payload, "expires_in_minutes")

      expires_at =
        if is_integer(expires_in_minutes) do
          DateTime.utc_now() |> DateTime.add(expires_in_minutes, :minute) |> DateTime.truncate(:second)
        end

      attrs = %{
        email: email,
        expires_at: expires_at,
        invited_by_id: socket.assigns.current_user.id
      }

      case Projects.create_project_invite(project.id, attrs) do
        {:ok, invite} ->
          url = "#{frontend_url()}/invite/#{invite.token}"
          if email, do: UserNotifier.deliver_project_invite_link(email, project.name, url)
          {:reply, {:ok, Map.put(invite_view(invite), :url, url)}, socket}

        {:error, changeset} ->
          {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
      end
    end)
  end

  def handle_in("revoke_invite", %{"id" => id}, socket) do
    with_owned_project(socket, fn project ->
      case Projects.get_project_invite_by_id(id, project.id) do
        %ProjectInvite{} = invite ->
          {:ok, _} = Projects.delete_project_invite(invite)
          {:reply, {:ok, %{id: id}}, socket}

        nil ->
          {:reply, {:error, %{message: "invite_not_found"}}, socket}
      end
    end)
  end

  def handle_in("remove_member", %{"user_id" => user_id}, socket) do
    with_owned_project(socket, fn project ->
      {:ok, _} = Projects.remove_member(project.id, user_id)

      for task <- Projects.unassign_user_from_tasks(project.id, user_id) do
        broadcast!(socket, "task_updated", task_view(task))
      end

      broadcast_users(project)
      Endpoint.broadcast("projects:user:#{user_id}", "project_deleted", %{id: project.id})
      {:reply, {:ok, %{user_id: user_id}}, socket}
    end)
  end

  def handle_in("set_public_link", %{"public_link" => public_link}, socket) do
    with_owned_project(socket, fn project ->
      case Projects.set_project_visibility(project, %{public_link: !!public_link}) do
        {:ok, updated} ->
          view = project_view(updated)
          broadcast!(socket, "project_updated", view)

          for member_id <- Projects.member_user_ids(updated.id) do
            Endpoint.broadcast("projects:user:#{member_id}", "project_updated", view)
          end

          {:reply, {:ok, view}, socket}

        {:error, changeset} ->
          {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
      end
    end)
  end

  def handle_in("set_project_theme", payload, socket) do
    with_owned_project(socket, fn project ->
      case Projects.set_project_theme(project, Map.get(payload, "theme_slug")) do
        {:ok, updated} ->
          view = project_view(updated)
          broadcast!(socket, "project_updated", view)

          for member_id <- Projects.member_user_ids(updated.id) do
            Endpoint.broadcast("projects:user:#{member_id}", "project_updated", view)
          end

          {:reply, {:ok, view}, socket}

        {:error, changeset} ->
          {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
      end
    end)
  end

  def handle_in("set_my_project_theme", payload, socket) do
    project_id = socket.assigns.project_id
    user_id = socket.assigns.current_user.id

    case Projects.set_user_project_theme(project_id, user_id, Map.get(payload, "theme_slug")) do
      {:ok, slug} -> {:reply, {:ok, %{theme_slug: slug}}, socket}
      {:error, changeset} -> {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
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
      text_color: Map.get(payload, "text_color") || "white",
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
    attrs = take_present(payload, ["name", "description", "color", "text_color"])

    with %Kaska.Projects.TaskType{} = task_type <- get_owned_task_type(id, socket),
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
    with %Kaska.Projects.TaskType{} = task_type <- get_owned_task_type(id, socket),
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

  defp with_owned_project(socket, fun) do
    user = socket.assigns[:current_user]
    project = Projects.get_project(socket.assigns.project_id)

    if user && project && Projects.owner?(project, user.id) do
      fun.(project)
    else
      {:reply, {:error, %{message: "forbidden", code: "forbidden"}}, socket}
    end
  end

  defp normalize_invite_email(nil), do: nil
  defp normalize_invite_email(""), do: nil

  defp normalize_invite_email(value) when is_binary(value),
    do: value |> String.downcase() |> String.trim()

  defp normalize_invite_email(_), do: nil

  defp frontend_url, do: System.get_env("WEB_BASE_URL", "http://localhost:5173")

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

  defp get_owned_task_type(id, socket) do
    case Projects.get_task_type(id) do
      %Kaska.Projects.TaskType{project_id: pid} = tt when pid == socket.assigns.project_id -> tt
      _ -> nil
    end
  end

  defp get_owned_task_comment(id, socket) do
    case Projects.get_task_comment(id) do
      %TaskComment{project_id: pid} = c when pid == socket.assigns.project_id -> c
      _ -> nil
    end
  end

  defp project_view(%Project{} = p) do
    %{
      id: p.id,
      slug: p.slug,
      name: p.name,
      description: p.description,
      owner_id: p.owner_id,
      public_link: p.public_link,
      theme_slug: p.theme_slug,
      avatar_url: media_url(p.avatar_key),
      background_url: media_url(p.background_key)
    }
  end

  defp member_view(%ProjectMember{} = m) do
    %{
      user_id: m.user_id,
      role: m.role,
      email: m.user && m.user.email,
      display_name: m.user && m.user.display_name,
      avatar_url: m.user && avatar_url(m.user),
      inserted_at: m.inserted_at
    }
  end

  defp invite_view(%ProjectInvite{} = i) do
    %{
      id: i.id,
      token: i.token,
      email: i.email,
      expires_at: i.expires_at,
      accepted_at: i.accepted_at,
      inserted_at: i.inserted_at
    }
  end

  defp media_url(nil), do: nil

  defp media_url(key) when is_binary(key) do
    case Kaska.Storage.presigned_get(key, expires_in: 3600 * 6) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp column_view(%Column{} = c) do
    %{id: c.id, project_id: c.project_id, name: c.name, rank: c.rank}
  end

  def task_view(%Task{} = t) do
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

  defp task_type_view(%Kaska.Projects.TaskType{} = tt) do
    %{
      id: tt.id,
      project_id: tt.project_id,
      name: tt.name,
      description: tt.description,
      color: tt.color,
      text_color: tt.text_color
    }
  end

  def broadcast_users(%Project{} = project) do
    payload = %{users: users_view(project.id)}
    Endpoint.broadcast("board:#{project.id}", "board_users", payload)

    if is_binary(project.slug) do
      Endpoint.broadcast("board_slug:#{project.slug}", "board_users", payload)
    end

    :ok
  end

  defp users_view(project_id) do
    project_id |> Projects.list_member_users() |> Enum.map(&user_view/1)
  end

  defp user_view(%Kaska.Accounts.User{} = u) do
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
    case Kaska.Storage.presigned_get(key, expires_in: 3600 * 6) do
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

  defp task_comment_view(%TaskComment{} = c) do
    %{
      id: c.id,
      task_id: c.task_id,
      project_id: c.project_id,
      body: c.body,
      author_id: c.author_id,
      guest_name: c.guest_name,
      author_display_name: c.author && c.author.display_name,
      author_email: c.author && c.author.email,
      author_avatar_url: c.author && avatar_url(c.author),
      author_role: c.author && c.author.role,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  defp can_delete_comment?(_comment, nil), do: false

  defp can_delete_comment?(%TaskComment{author_id: nil}, _actor), do: true

  defp can_delete_comment?(%TaskComment{author_id: author_id}, %{id: actor_id})
       when author_id == actor_id,
       do: true

  defp can_delete_comment?(%TaskComment{} = comment, actor) do
    case Accounts.get_user(comment.author_id) do
      nil -> true
      author -> role_rank(actor.role) > role_rank(author.role)
    end
  end

  defp role_rank(:user), do: 1
  defp role_rank(:admin), do: 2
  defp role_rank(:superadmin), do: 3
  defp role_rank(_), do: 0

  defp check_guest_comment_rate(socket, task_id) do
    ensure_guest_comment_rate_table!()
    key = {task_id, socket.transport_pid}
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@guest_comment_rate_table, key) do
      [{^key, prev}] when now - prev < @guest_comment_min_interval_ms ->
        {:error, :rate_limited}

      _ ->
        true = :ets.insert(@guest_comment_rate_table, {key, now})
        :ok
    end
  end

  defp ensure_guest_comment_rate_table! do
    case :ets.whereis(@guest_comment_rate_table) do
      :undefined ->
        :ets.new(@guest_comment_rate_table, [
          :named_table,
          :public,
          :set,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  rescue
    ArgumentError -> :ok
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
