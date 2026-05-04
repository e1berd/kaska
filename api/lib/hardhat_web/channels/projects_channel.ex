defmodule HardhatWeb.ProjectsChannel do
  @moduledoc """
  `projects:lobby` — public listing + authed creation.

  Mutations broadcast a `project_created` event to all subscribers so other
  clients refresh their list in realtime.
  """

  use Phoenix.Channel

  alias Hardhat.Projects
  alias Hardhat.Projects.Project

  @impl true
  def join("projects:lobby", _payload, socket) do
    {:ok, %{projects: Enum.map(Projects.list_projects(), &project_view/1)}, socket}
  end

  @impl true
  def handle_in("list_projects", _payload, socket) do
    {:reply, {:ok, %{projects: Enum.map(Projects.list_projects(), &project_view/1)}}, socket}
  end

  def handle_in("create_project", _payload, %{assigns: %{current_user: nil}} = socket) do
    {:reply, {:error, %{message: "unauthorized", code: "unauthorized"}}, socket}
  end

  def handle_in("create_project", payload, socket) do
    %{assigns: %{current_user: user}} = socket

    attrs = %{
      slug: Map.get(payload, "slug"),
      name: Map.get(payload, "name"),
      description: Map.get(payload, "description")
    }

    case Projects.create_project(user.id, attrs) do
      {:ok, project} ->
        view = project_view(project)
        broadcast!(socket, "project_created", view)
        {:reply, {:ok, view}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  defp project_view(%Project{} = p) do
    %{
      id: p.id,
      slug: p.slug,
      name: p.name,
      description: p.description,
      owner_id: p.owner_id,
      inserted_at: p.inserted_at
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
