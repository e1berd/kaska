defmodule KaskaWeb.Api.BoardController do
  use KaskaWeb, :controller

  alias Kaska.Projects
  alias KaskaWeb.Api.Serializer

  plug KaskaWeb.Plugs.RunnerAuth

  def project(conn, _params) do
    project = conn.assigns.project
    {_project, columns, _tasks} = Projects.board_snapshot(project.id)
    json(conn, %{project: Serializer.project(project, columns)})
  end
end
