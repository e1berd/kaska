defmodule KaskaWeb.Api.BoardController do
  use KaskaWeb, :controller

  alias Kaska.Projects
  alias KaskaWeb.Api.Serializer

  plug KaskaWeb.Plugs.ApiProject

  action_fallback KaskaWeb.Api.FallbackController

  def project(conn, _params) do
    project = conn.assigns.project
    {_project, columns, _tasks} = Projects.board_snapshot(project.id)
    json(conn, %{project: Serializer.project(project, columns)})
  end

  def columns(conn, _params) do
    {_project, columns, _tasks} = Projects.board_snapshot(conn.assigns.project.id)
    json(conn, %{columns: Enum.map(columns, &Serializer.column/1)})
  end

  def task_types(conn, _params) do
    types = Projects.list_task_types(conn.assigns.project.id)
    json(conn, %{task_types: Enum.map(types, &Serializer.task_type/1)})
  end

  def members(conn, _params) do
    users = Projects.list_member_users(conn.assigns.project.id)
    json(conn, %{members: Enum.map(users, &Serializer.user_brief/1)})
  end
end
