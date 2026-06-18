defmodule KaskaWeb.Api.Serializer do
  @moduledoc """
  JSON shapes for the REST API. Agent-facing and deliberately flatter than the
  channel views: task bodies are rendered per the requested `format`
  (`:markdown` string or `:json` tiptap document), and related records are
  nested rather than referenced by id.
  """

  alias Kaska.Attachments
  alias Kaska.TaskBody

  alias Kaska.Accounts.User
  alias Kaska.Attachments.Attachment
  alias Kaska.Projects.{Column, Project, Task, TaskComment, TaskType}

  def project_brief(%Project{} = p) do
    %{id: p.id, slug: p.slug, name: p.name, description: p.description}
  end

  def project(%Project{} = p, columns) do
    %{
      id: p.id,
      slug: p.slug,
      name: p.name,
      description: p.description,
      agent_instructions: p.agent_instructions,
      columns: Enum.map(columns, &column/1)
    }
  end

  def task(%Task{} = task, comments_by_task, attachments_by_task, format) do
    %{
      id: task.id,
      title: task.title,
      body: TaskBody.body_view(task.body_doc, format),
      body_format: format,
      column: column(task.column),
      type: task_type(task.task_type),
      assignee: user_brief(task.assignee),
      creator: user_brief(task.creator),
      rank: task.rank,
      start_date: task.start_date,
      end_date: task.end_date,
      inserted_at: task.inserted_at,
      updated_at: task.updated_at,
      comments: comments_by_task |> Map.get(task.id, []) |> Enum.map(&comment(&1, format)),
      attachments: attachments_by_task |> Map.get(task.id, []) |> Enum.map(&attachment/1)
    }
  end

  def column(%Column{} = c) do
    %{id: c.id, name: c.name, rank: c.rank, description: c.description, color: c.color}
  end

  def column(_), do: nil

  def task_type(%TaskType{} = tt) do
    %{
      id: tt.id,
      name: tt.name,
      description: tt.description,
      color: tt.color,
      text_color: tt.text_color
    }
  end

  def task_type(_), do: nil

  def comment(%TaskComment{} = c, format \\ :markdown) do
    %{
      id: c.id,
      task_id: c.task_id,
      parent_id: c.parent_id,
      body: TaskBody.body_view(c.body_doc, format),
      body_format: format,
      author: user_brief(maybe_loaded(c.author)),
      guest_name: c.guest_name,
      attachments: "comment" |> Attachments.list_for(c.id) |> Enum.map(&attachment/1),
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end

  def attachment(%Attachment{} = a) do
    %{
      id: a.id,
      filename: a.filename,
      mime: a.mime,
      size: a.size,
      kind: a.kind,
      url: Attachments.view_url(a)
    }
  end

  def user_brief(%User{} = u) do
    %{id: u.id, email: u.email, display_name: u.display_name, is_agent: u.is_agent}
  end

  def user_brief(_), do: nil

  defp maybe_loaded(%Ecto.Association.NotLoaded{}), do: nil
  defp maybe_loaded(other), do: other
end
