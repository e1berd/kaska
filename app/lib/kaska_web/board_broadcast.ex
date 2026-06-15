defmodule KaskaWeb.BoardBroadcast do
  @moduledoc """
  Pushes board deltas from outside a channel process (e.g. the REST API) onto
  the `board:*` topics so connected web clients reconcile in realtime. Payloads
  reuse `KaskaWeb.BoardChannel` views to stay in sync with the channel's own
  broadcasts.
  """

  alias Kaska.Projects.{Project, Task, TaskComment}
  alias KaskaWeb.{BoardChannel, Endpoint}

  def task(%Project{} = project, event, %Task{} = task) do
    emit(project, event, BoardChannel.task_view(task))
  end

  def comment_created(%Project{} = project, %TaskComment{} = comment) do
    emit(project, "task_comment_created", BoardChannel.task_comment_view(comment))
  end

  defp emit(%Project{} = project, event, payload) do
    Endpoint.broadcast("board:#{project.id}", event, payload)

    if is_binary(project.slug) do
      Endpoint.broadcast("board_slug:#{project.slug}", event, payload)
    end

    :ok
  end
end
