defmodule KaskaWeb.Api.CommentController do
  use KaskaWeb, :controller

  alias Kaska.Projects
  alias KaskaWeb.Api.Serializer
  alias KaskaWeb.BoardBroadcast

  plug KaskaWeb.Plugs.ApiProject

  action_fallback KaskaWeb.Api.FallbackController

  def index(conn, %{"task_id" => task_id}) do
    project = conn.assigns.project

    case Projects.get_project_task(project.id, task_id) do
      nil ->
        {:error, :not_found}

      _task ->
        comments = Projects.list_task_comments_for(project.id, task_id)
        json(conn, %{comments: Enum.map(comments, &Serializer.comment/1)})
    end
  end

  def create(conn, %{"task_id" => task_id} = params) do
    project = conn.assigns.project
    author = conn.assigns.current_user
    attrs = %{body: Map.get(params, "body", "")}

    with {:ok, comment} <- Projects.create_task_comment(project.id, task_id, attrs, author.id) do
      BoardBroadcast.comment_created(project, comment)

      conn
      |> put_status(:created)
      |> json(%{comment: Serializer.comment(comment)})
    end
  end
end
