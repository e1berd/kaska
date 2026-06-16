defmodule KaskaWeb.Api.CommentController do
  use KaskaWeb, :controller

  alias Kaska.{Projects, TaskBody}
  alias KaskaWeb.Api.Serializer
  alias KaskaWeb.BoardBroadcast

  plug KaskaWeb.Plugs.ApiProject

  action_fallback KaskaWeb.Api.FallbackController

  def index(conn, %{"task_id" => task_id} = params) do
    project = conn.assigns.project
    format = format(params)

    case Projects.get_project_task(project.id, task_id) do
      nil ->
        {:error, :not_found}

      _task ->
        comments = Projects.list_task_comments_for(project.id, task_id)
        json(conn, %{comments: Enum.map(comments, &Serializer.comment(&1, format))})
    end
  end

  def create(conn, %{"task_id" => task_id} = params) do
    project = conn.assigns.project
    author = conn.assigns.current_user
    format = format(params)

    attrs =
      %{}
      |> put_body(params)
      |> put_present(params, "parent_id", :parent_id)

    with {:ok, comment} <- Projects.create_task_comment(project.id, task_id, attrs, author.id) do
      BoardBroadcast.comment_created(project, comment)

      conn
      |> put_status(:created)
      |> json(%{comment: Serializer.comment(comment, format)})
    end
  end

  defp format(params),
    do: TaskBody.normalize_format(params["task_format"] || params["taskFormat"])

  defp put_body(attrs, params) do
    cond do
      Map.has_key?(params, "body_doc") -> Map.put(attrs, :body_doc, params["body_doc"])
      Map.has_key?(params, "body") -> Map.put(attrs, :body, params["body"])
      true -> attrs
    end
  end

  defp put_present(attrs, params, key, field) do
    case Map.fetch(params, key) do
      {:ok, value} -> Map.put(attrs, field, value)
      :error -> attrs
    end
  end
end
