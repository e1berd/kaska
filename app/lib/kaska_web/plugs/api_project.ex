defmodule KaskaWeb.Plugs.ApiProject do
  @moduledoc """
  Loads the project named by the `:project_slug` path param and authorizes the
  authenticated user against it. The REST API is for project members acting as
  agents, so membership is required for both reads and writes. Assigns
  `:project` and `:can_write`.
  """

  import Plug.Conn

  alias Kaska.Projects

  def init(opts), do: opts

  def call(conn, _opts) do
    user = conn.assigns.current_user

    case Projects.get_project_by_slug(conn.params["project_slug"]) do
      nil ->
        halt_json(conn, 404, %{error: "project_not_found"})

      project ->
        if Projects.member?(project.id, user.id) do
          conn
          |> assign(:project, project)
          |> assign(:can_write, true)
        else
          halt_json(conn, 403, %{error: "forbidden"})
        end
    end
  end

  defp halt_json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
