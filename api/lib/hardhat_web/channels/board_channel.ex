defmodule HardhatWeb.BoardChannel do
  @moduledoc """
  `board:<project_id>` — public read, authed write.

  On join: returns a snapshot of `{project, columns, tasks}` so a fresh client
  (including anonymous guests) can render the board immediately.

  Mutations broadcast deltas (`column_created`, `task_moved`, …) to all
  subscribers of the topic. Clients reconcile their local state from these.
  """

  use Phoenix.Channel

  alias Hardhat.Projects
  alias Hardhat.Projects.{Column, Project, Task}

  @impl true
  def join("board:" <> project_id, _payload, socket) do
    case Projects.board_snapshot(project_id) do
      nil ->
        {:error, %{reason: "not_found"}}

      {project, columns, tasks} ->
        socket = assign(socket, :project_id, project.id)

        {:ok,
         %{
           project: project_view(project),
           columns: Enum.map(columns, &column_view/1),
           tasks: Enum.map(tasks, &task_view/1)
         }, socket}
    end
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

  ## Tasks ───────────────────────────────────────────────────────────────

  def handle_in("create_task", %{"column_id" => column_id} = payload, socket) do
    project_id = socket.assigns.project_id
    creator_id = socket.assigns.current_user.id

    attrs = %{
      title: Map.get(payload, "title"),
      description: Map.get(payload, "description")
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
    with %Task{} = task <- get_owned_task(id, socket),
         {:ok, task} <-
           Projects.update_task(task, %{
             title: Map.get(payload, "title"),
             description: Map.get(payload, "description")
           }) do
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
      broadcast!(socket, "task_deleted", %{id: id})
      {:reply, {:ok, %{id: id}}, socket}
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
      description: t.description,
      rank: t.rank,
      creator_id: t.creator_id,
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
