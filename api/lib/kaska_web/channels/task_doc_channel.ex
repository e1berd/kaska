defmodule KaskaWeb.TaskDocChannel do
  @moduledoc false

  use Phoenix.Channel

  alias Kaska.Projects
  alias Kaska.Projects.{Project, Task}
  alias Kaska.TaskDocs
  alias KaskaWeb.Presence

  @impl true
  def join("task_doc:" <> task_id, _payload, socket) do
    with %Task{} = task <- Projects.get_task(task_id),
         %Project{} = project <- Projects.get_project(task.project_id),
         {:ok, _pid} <- Kaska.TaskDocs.Supervisor.lookup_or_start(task.id),
         {:ok, state_bin} <- TaskDocs.Server.get_state(task.id) do
      socket =
        socket
        |> assign(:task_id, task.id)
        |> assign(:project_id, task.project_id)
        |> assign(:project_slug, project.slug)

      send(self(), :after_join)

      {:ok, %{state: Base.encode64(state_bin)}, socket}
    else
      nil -> {:error, %{reason: "not_found"}}
      _ -> {:error, %{reason: "server_unavailable"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    if user = socket.assigns[:current_user] do
      {:ok, _} =
        Presence.track(socket, user.id, %{
          online_at: inspect(System.system_time(:second))
        })
    end

    push(socket, "presence_state", Presence.list(socket))
    {:noreply, socket}
  end

  @impl true
  def handle_in(_event, _payload, %{assigns: %{current_user: nil}} = socket) do
    {:reply, {:error, %{message: "unauthorized"}}, socket}
  end

  def handle_in("update", %{"u" => b64}, socket) when is_binary(b64) do
    with {:ok, bin} <- Base.decode64(b64),
         author_id = socket.assigns.current_user.id,
         :ok <- TaskDocs.Server.apply_update(socket.assigns.task_id, bin, author_id) do
      broadcast_from!(socket, "update", %{u: b64})
      {:reply, :ok, socket}
    else
      :error -> {:reply, {:error, %{message: "invalid_base64"}}, socket}
      {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  def handle_in("awareness", %{"s" => b64}, socket) when is_binary(b64) do
    user = socket.assigns.current_user
    broadcast_from!(socket, "awareness", %{s: b64, from: user.id})
    {:reply, :ok, socket}
  end

  def handle_in("materialize_body_doc", %{"doc" => %{"type" => "doc"} = doc}, socket) do
    case TaskDocs.update_body_doc(socket.assigns.task_id, doc) do
      :ok ->
        broadcast_task_update(socket)
        {:reply, :ok, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  def handle_in("materialize_body_doc", _payload, socket) do
    {:reply, {:error, %{message: "invalid_doc"}}, socket}
  end

  defp broadcast_task_update(socket) do
    case Projects.get_task(socket.assigns.task_id) do
      %Task{} = task ->
        view = KaskaWeb.BoardChannel.task_view(task)

        KaskaWeb.Endpoint.broadcast!(
          "board:#{socket.assigns.project_id}",
          "task_updated",
          view
        )

        if slug = socket.assigns[:project_slug] do
          KaskaWeb.Endpoint.broadcast!("board_slug:#{slug}", "task_updated", view)
        end

      _ ->
        :ok
    end
  end
end
