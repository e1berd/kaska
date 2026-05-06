defmodule Hardhat.Projects do
  @moduledoc """
  Projects, columns and tasks. Reads are public; mutations are authorized in
  the channel layer (this context trusts its callers).

  Ordering uses `Hardhat.Rank` (fractional indexing). Move/reorder takes the
  ids of the new neighbours (`before_id`, `after_id`) and the server computes
  the rank between their current ranks — server-authoritative, conflict-safe.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Hardhat.Repo
  alias Hardhat.Rank
  alias Hardhat.Projects.{Column, Project, Task, TaskType}

  @default_columns [
    {"Todo", "F"},
    {"In Progress", "U"},
    {"Done", "k"}
  ]

  ## Projects ─────────────────────────────────────────────────────────────

  def list_projects do
    Repo.all(from p in Project, order_by: [asc: p.inserted_at])
  end

  def get_project(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get(Project, id)
      :error -> nil
    end
  end

  def get_project(_), do: nil

  def get_project_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Project, slug: slug |> String.downcase() |> String.trim())
  end

  def get_project_by_slug(_), do: nil

  ## Task Types ─────────────────────────────────────────────────────────

  def list_task_types(project_id) do
    Repo.all(from t in TaskType, where: t.project_id == ^project_id, order_by: t.name)
  end

  def get_task_type(id), do: Repo.get(TaskType, id)

  def create_task_type(attrs \\ %{}) do
    %TaskType{}
    |> TaskType.changeset(attrs)
    |> Repo.insert()
  end

  def update_task_type(%TaskType{} = task_type, attrs) do
    task_type
    |> TaskType.changeset(attrs)
    |> Repo.update()
  end

  def delete_task_type(%TaskType{} = task_type) do
    Repo.delete(task_type)
  end

  @doc """
  Creates a project owned by `owner_id` and seeds three default columns
  (Todo / In Progress / Done) inside the same transaction.
  """
  def create_project(owner_id, attrs) when is_binary(owner_id) do
    project_attrs = attrs |> Map.new() |> Map.put(:owner_id, owner_id)

    multi =
      Multi.new()
      |> Multi.insert(:project, Project.create_changeset(%Project{}, project_attrs))
      |> Multi.run(:columns, fn repo, %{project: project} ->
        columns =
          for {name, rank} <- @default_columns do
            %Column{}
            |> Column.create_changeset(%{name: name, rank: rank, project_id: project.id})
            |> repo.insert!()
          end

        {:ok, columns}
      end)

    case Repo.transaction(multi) do
      {:ok, %{project: project}} -> {:ok, project}
      {:error, :project, changeset, _} -> {:error, changeset}
    end
  end

  def update_project(%Project{} = project, attrs) do
    project
    |> Project.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  ## Board snapshot ───────────────────────────────────────────────────────

  @doc """
  Returns `{project, columns, tasks}` for a board, ordered by rank.
  Returns `nil` if the project doesn't exist.
  """
  def board_snapshot(project_id) when is_binary(project_id) do
    case get_project(project_id) do
      nil ->
        nil

      project ->
        columns =
          Repo.all(
            from c in Column,
              where: c.project_id == ^project_id,
              order_by: [asc: c.rank]
          )

        tasks =
          Repo.all(
            from t in Task,
              where: t.project_id == ^project_id,
              order_by: [asc: t.rank]
          )

        {project, columns, tasks}
    end
  end

  ## Columns ──────────────────────────────────────────────────────────────

  def get_column(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get(Column, id)
      :error -> nil
    end
  end

  def get_column(_), do: nil

  @doc "Creates a column at the end of the project's column list."
  def create_column(project_id, attrs) when is_binary(project_id) do
    last_rank = last_column_rank(project_id)
    rank = Rank.between(last_rank, nil)

    %Column{}
    |> Column.create_changeset(
      attrs
      |> Map.new()
      |> Map.put(:project_id, project_id)
      |> Map.put(:rank, rank)
    )
    |> Repo.insert()
  end

  def rename_column(%Column{} = column, attrs) do
    column
    |> Column.rename_changeset(attrs)
    |> Repo.update()
  end

  def delete_column(%Column{} = column), do: Repo.delete(column)

  @doc """
  Moves `column` between `before_id` and `after_id` in the same project.
  Either neighbour may be `nil`.
  """
  def move_column(%Column{project_id: project_id} = column, before_id, after_id) do
    with {:ok, before_rank} <- column_rank(project_id, before_id),
         {:ok, after_rank} <- column_rank(project_id, after_id),
         {:ok, rank} <- safe_rank_between(before_rank, after_rank) do
      column
      |> Column.rank_changeset(%{rank: rank})
      |> Repo.update()
    end
  end

  defp last_column_rank(project_id) do
    Repo.one(
      from c in Column,
        where: c.project_id == ^project_id,
        order_by: [desc: c.rank],
        limit: 1,
        select: c.rank
    )
  end

  defp column_rank(_project_id, nil), do: {:ok, nil}

  defp column_rank(project_id, id) when is_binary(id) do
    case Repo.one(
           from c in Column,
             where: c.id == ^id and c.project_id == ^project_id,
             select: c.rank
         ) do
      nil -> {:error, :neighbour_not_found}
      rank -> {:ok, rank}
    end
  end

  ## Tasks ────────────────────────────────────────────────────────────────

  def get_task(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get(Task, id)
      :error -> nil
    end
  end

  def get_task(_), do: nil

  @empty_doc %{"type" => "doc", "content" => []}

  @doc """
  Creates a task at the end of `column_id` (which must belong to `project_id`).
  """
  def create_task(project_id, column_id, attrs, creator_id) do
    with %Column{project_id: ^project_id} <- get_column(column_id) do
      last_rank = last_task_rank(column_id)
      rank = Rank.between(last_rank, nil)

      attrs =
        attrs
        |> Map.new()
        |> Map.put(:project_id, project_id)
        |> Map.put(:column_id, column_id)
        |> Map.put(:creator_id, creator_id)
        |> Map.put(:rank, rank)
        |> Map.put_new(:body_doc, @empty_doc)
        |> Map.put_new(:start_date, DateTime.utc_now() |> DateTime.truncate(:second))

      %Task{}
      |> Task.create_changeset(attrs)
      |> Repo.insert()
    else
      _ -> {:error, :column_not_found}
    end
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)

  @doc """
  Moves `task` to `target_column_id` between `before_id` and `after_id`
  (both task ids inside the target column; either can be nil).
  """
  def move_task(%Task{} = task, target_column_id, before_id, after_id) do
    with %Column{project_id: project_id} <- get_column(target_column_id),
         true <- project_id == task.project_id || {:error, :cross_project},
         {:ok, before_rank} <- task_rank(target_column_id, before_id),
         {:ok, after_rank} <- task_rank(target_column_id, after_id),
         {:ok, rank} <- safe_rank_between(before_rank, after_rank) do
      task
      |> Task.move_changeset(%{column_id: target_column_id, rank: rank})
      |> Repo.update()
    else
      nil -> {:error, :column_not_found}
      {:error, _} = err -> err
      false -> {:error, :cross_project}
    end
  end

  defp last_task_rank(column_id) do
    Repo.one(
      from t in Task,
        where: t.column_id == ^column_id,
        order_by: [desc: t.rank],
        limit: 1,
        select: t.rank
    )
  end

  defp task_rank(_column_id, nil), do: {:ok, nil}

  defp task_rank(column_id, id) when is_binary(id) do
    case Repo.one(
           from t in Task,
             where: t.id == ^id and t.column_id == ^column_id,
             select: t.rank
         ) do
      nil -> {:error, :neighbour_not_found}
      rank -> {:ok, rank}
    end
  end

  defp safe_rank_between(prev, next) do
    {:ok, Rank.between(prev, next)}
  rescue
    ArgumentError -> {:error, :invalid_neighbours}
  end
end
