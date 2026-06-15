defmodule KaskaWeb.Api.ProjectController do
  use KaskaWeb, :controller

  alias Kaska.Projects
  alias KaskaWeb.Api.Serializer

  action_fallback KaskaWeb.Api.FallbackController

  def index(conn, _params) do
    projects = Projects.list_projects(conn.assigns.current_user.id)
    json(conn, %{projects: Enum.map(projects, &Serializer.project_brief/1)})
  end
end
