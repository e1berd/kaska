defmodule KaskaWeb.Api.TaskController do
  use KaskaWeb, :controller

  alias Kaska.{Attachments, Projects, TaskBody}
  alias Kaska.Projects.Task
  alias KaskaWeb.Api.Serializer
  alias KaskaWeb.BoardBroadcast

  plug KaskaWeb.Plugs.ApiProject

  action_fallback KaskaWeb.Api.FallbackController

  def index(conn, params) do
    project = conn.assigns.project
    format = format(params)
    tasks = Projects.list_tasks(project.id)

    comments_by_task =
      project.id |> Projects.list_task_comments() |> Enum.group_by(& &1.task_id)

    attachments_by_task =
      Attachments.list_for_many("task", Enum.map(tasks, & &1.id))

    json(conn, %{
      tasks: Enum.map(tasks, &Serializer.task(&1, comments_by_task, attachments_by_task, format))
    })
  end

  def show(conn, %{"id" => id} = params) do
    project = conn.assigns.project

    case Projects.get_project_task(project.id, id) do
      nil -> {:error, :not_found}
      task -> json(conn, %{task: render_task(project, task, format(params))})
    end
  end

  def update(conn, %{"id" => id} = params) do
    project = conn.assigns.project

    with %Task{} = task <- Projects.get_project_task(project.id, id),
         {:ok, updated} <- Projects.update_task(task, update_attrs(params)) do
      reloaded = Projects.get_project_task(project.id, updated.id)
      BoardBroadcast.task(project, "task_updated", reloaded)
      json(conn, %{task: render_task(project, reloaded, format(params))})
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def create(conn, %{"column_id" => column_id} = params) do
    project = conn.assigns.project
    creator = conn.assigns.current_user

    attrs = %{
      title: Map.get(params, "title"),
      start_date: Map.get(params, "start_date"),
      end_date: Map.get(params, "end_date"),
      assignee_id: Map.get(params, "assignee_id"),
      task_type_id: Map.get(params, "task_type_id")
    }

    body_doc =
      cond do
        Map.has_key?(params, "body_doc") -> params["body_doc"]
        Map.has_key?(params, "body") -> TaskBody.from_markdown(params["body"])
        true -> nil
      end

    attrs = if body_doc, do: Map.put(attrs, :body_doc, body_doc), else: attrs

    case Projects.create_task(project.id, column_id, attrs, creator.id) do
      {:ok, task} ->
        BoardBroadcast.task(project, "task_created", task)

        conn
        |> put_status(:created)
        |> json(%{task: render_task(project, task, format(params))})

      {:error, %Ecto.Changeset{} = cs} ->
        {:error, cs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "column_id_required"})
  end

  def move(conn, %{"id" => id, "column_id" => column_id} = params) do
    project = conn.assigns.project

    with %Task{} = task <- Projects.get_project_task(project.id, id),
         {before_id, after_id} <- position(column_id, task, params),
         {:ok, moved} <- Projects.move_task(task, column_id, before_id, after_id) do
      reloaded = Projects.get_project_task(project.id, moved.id)
      BoardBroadcast.task(project, "task_moved", reloaded)
      json(conn, %{task: render_task(project, reloaded, format(params))})
    else
      nil -> {:error, :not_found}
      other -> other
    end
  end

  def delete(conn, %{"id" => id}) do
    project = conn.assigns.project

    with %Task{} = task <- Projects.get_project_task(project.id, id) do
      Projects.delete_task(task)
      BoardBroadcast.task(project, "task_deleted", task)
      json(conn, %{ok: true})
    else
      nil -> {:error, :not_found}
    end
  end

  defp render_task(project, task, format) do
    comments = %{task.id => Projects.list_task_comments_for(project.id, task.id)}
    attachments = Attachments.list_for_many("task", [task.id])
    Serializer.task(task, comments, attachments, format)
  end

  defp format(params),
    do: TaskBody.normalize_format(params["task_format"] || params["taskFormat"])

  defp position(column_id, task, params) do
    before_id = params["before_id"]
    after_id = params["after_id"]

    if is_nil(before_id) and is_nil(after_id) do
      {Projects.last_task_id(column_id, task.id), nil}
    else
      {before_id, after_id}
    end
  end

  defp update_attrs(params) do
    %{}
    |> put_present(params, "title", :title)
    |> put_body(params)
    |> put_present(params, "assignee_id", :assignee_id)
    |> put_present(params, "task_type_id", :task_type_id)
    |> put_present(params, "start_date", :start_date)
    |> put_present(params, "end_date", :end_date)
  end

  defp put_present(attrs, params, key, field) do
    case Map.fetch(params, key) do
      {:ok, value} -> Map.put(attrs, field, value)
      :error -> attrs
    end
  end

  defp put_body(attrs, params) do
    cond do
      Map.has_key?(params, "body_doc") ->
        Map.put(attrs, :body_doc, params["body_doc"])

      Map.has_key?(params, "body") ->
        Map.put(attrs, :body_doc, TaskBody.from_markdown(params["body"]))

      true ->
        attrs
    end
  end
end
