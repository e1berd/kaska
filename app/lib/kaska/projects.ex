defmodule Kaska.Projects do
  @moduledoc """
  Projects, columns and tasks. Reads are public; mutations are authorized in
  the channel layer (this context trusts its callers).

  Ordering uses `Kaska.Rank` (fractional indexing). Move/reorder takes the
  ids of the new neighbours (`before_id`, `after_id`) and the server computes
  the rank between their current ranks — server-authoritative, conflict-safe.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Kaska.Repo
  alias Kaska.Rank
  alias Kaska.TaskBody
  alias Kaska.AgentEvents
  alias Kaska.Accounts.User

  alias Kaska.Projects.{
    Column,
    Project,
    ProjectInvite,
    ProjectMember,
    ProjectThemePref,
    Task,
    TaskComment,
    TaskType
  }

  @default_columns [
    {"Todo", "F"},
    {"In Progress", "U"},
    {"Done", "k"}
  ]

  ## Projects ─────────────────────────────────────────────────────────────

  def list_projects(user_id) when is_binary(user_id) do
    Repo.all(
      from p in Project,
        join: m in ProjectMember,
        on: m.project_id == p.id and m.user_id == ^user_id,
        order_by: [asc: p.inserted_at]
    )
  end

  def list_projects(_), do: []

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
      |> Multi.insert(:owner_membership, fn %{project: project} ->
        ProjectMember.changeset(%ProjectMember{}, %{
          project_id: project.id,
          user_id: owner_id,
          role: :owner
        })
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

  def set_project_media(%Project{} = project, attrs) do
    old_avatar = project.avatar_key
    old_background = project.background_key

    case project |> Project.media_changeset(attrs) |> Repo.update() do
      {:ok, updated} = ok ->
        if (Map.has_key?(attrs, :avatar_key) and old_avatar) &&
             old_avatar != updated.avatar_key,
           do: Kaska.Storage.delete_object(old_avatar)

        if (Map.has_key?(attrs, :background_key) and old_background) &&
             old_background != updated.background_key,
           do: Kaska.Storage.delete_object(old_background)

        ok

      err ->
        err
    end
  end

  def delete_project(%Project{} = project), do: Repo.delete(project)

  def set_project_visibility(%Project{} = project, attrs) do
    project
    |> Project.visibility_changeset(attrs)
    |> Repo.update()
  end

  ## Themes ────────────────────────────────────────────────────────────────

  def set_project_theme(%Project{} = project, slug) do
    project
    |> Project.theme_changeset(%{theme_slug: normalize_theme_slug(slug)})
    |> Repo.update()
  end

  def get_user_project_theme(project_id, user_id)
      when is_binary(project_id) and is_binary(user_id) do
    Repo.one(
      from p in ProjectThemePref,
        where: p.project_id == ^project_id and p.user_id == ^user_id,
        select: p.theme_slug
    )
  end

  def get_user_project_theme(_, _), do: nil

  def set_user_project_theme(project_id, user_id, slug)
      when is_binary(project_id) and is_binary(user_id) do
    case normalize_theme_slug(slug) do
      nil ->
        Repo.delete_all(
          from p in ProjectThemePref,
            where: p.project_id == ^project_id and p.user_id == ^user_id
        )

        {:ok, nil}

      normalized ->
        %ProjectThemePref{}
        |> ProjectThemePref.changeset(%{
          project_id: project_id,
          user_id: user_id,
          theme_slug: normalized
        })
        |> Repo.insert(
          on_conflict: {:replace, [:theme_slug, :updated_at]},
          conflict_target: [:project_id, :user_id]
        )
        |> case do
          {:ok, pref} -> {:ok, pref.theme_slug}
          other -> other
        end
    end
  end

  defp normalize_theme_slug(nil), do: nil
  defp normalize_theme_slug(""), do: nil
  defp normalize_theme_slug(slug) when is_binary(slug), do: String.trim(slug)
  defp normalize_theme_slug(_), do: nil

  ## Membership ────────────────────────────────────────────────────────────

  def member?(project_id, user_id) when is_binary(project_id) and is_binary(user_id) do
    Repo.exists?(
      from m in ProjectMember,
        where: m.project_id == ^project_id and m.user_id == ^user_id
    )
  end

  def member?(_, _), do: false

  def owner?(%Project{owner_id: owner_id}, user_id), do: owner_id == user_id
  def owner?(_, _), do: false

  def list_members(project_id) when is_binary(project_id) do
    Repo.all(
      from m in ProjectMember,
        where: m.project_id == ^project_id,
        order_by: [asc: m.inserted_at],
        preload: [:user]
    )
  end

  def add_member(project_id, user_id, role \\ :member)
      when is_binary(project_id) and is_binary(user_id) do
    %ProjectMember{}
    |> ProjectMember.changeset(%{project_id: project_id, user_id: user_id, role: role})
    |> Repo.insert(
      on_conflict: :nothing,
      conflict_target: [:project_id, :user_id]
    )
  end

  def remove_member(project_id, user_id) when is_binary(project_id) and is_binary(user_id) do
    {count, _} =
      Repo.delete_all(
        from m in ProjectMember,
          where: m.project_id == ^project_id and m.user_id == ^user_id and m.role != :owner
      )

    {:ok, count}
  end

  def member_user_ids(project_id) when is_binary(project_id) do
    Repo.all(from m in ProjectMember, where: m.project_id == ^project_id, select: m.user_id)
  end

  def list_member_users(project_id) when is_binary(project_id) do
    project_id |> list_members() |> Enum.map(& &1.user)
  end

  def board_accessible?(%Project{} = project, user_id) when is_binary(user_id) do
    project.public_link or member?(project.id, user_id)
  end

  def board_accessible?(%Project{} = project, _), do: project.public_link

  ## Project invites ───────────────────────────────────────────────────────

  def list_project_invites(project_id) when is_binary(project_id) do
    Repo.all(
      from i in ProjectInvite,
        where: i.project_id == ^project_id and is_nil(i.accepted_at),
        order_by: [desc: i.inserted_at]
    )
  end

  def get_project_invite_by_token(token) when is_binary(token) do
    Repo.get_by(ProjectInvite, token: token)
  end

  def get_project_invite_by_token(_), do: nil

  def get_project_invite_by_id(id, project_id) when is_binary(id) and is_binary(project_id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get_by(ProjectInvite, id: id, project_id: project_id)
      :error -> nil
    end
  end

  def get_project_invite_by_id(_, _), do: nil

  def create_project_invite(project_id, attrs) when is_binary(project_id) do
    token = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

    %ProjectInvite{}
    |> ProjectInvite.changeset(Map.merge(attrs, %{project_id: project_id, token: token}))
    |> Repo.insert()
  end

  def delete_project_invite(%ProjectInvite{} = invite), do: Repo.delete(invite)

  def accept_project_invite(token, user_id) when is_binary(token) and is_binary(user_id) do
    with %ProjectInvite{} = invite <- get_project_invite_by_token(token),
         :ok <- check_invite_live(invite),
         {:ok, _} <- add_member(invite.project_id, user_id, :member) do
      maybe_mark_accepted(invite)
      {:ok, get_project(invite.project_id)}
    else
      nil -> {:error, :invalid_invite}
      {:error, _} = err -> err
    end
  end

  defp maybe_mark_accepted(%ProjectInvite{email: nil}), do: :ok

  defp maybe_mark_accepted(%ProjectInvite{accepted_at: nil} = invite) do
    invite
    |> ProjectInvite.changeset(%{
      accepted_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  defp maybe_mark_accepted(_), do: :ok

  defp check_invite_live(%ProjectInvite{expires_at: nil}), do: :ok

  defp check_invite_live(%ProjectInvite{expires_at: expires_at}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, :expired}
    end
  end

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

  @task_api_preloads [:column, :task_type, :assignee, :creator]

  def list_tasks(project_id) when is_binary(project_id) do
    Repo.all(
      from t in Task,
        where: t.project_id == ^project_id,
        order_by: [asc: t.rank],
        preload: ^@task_api_preloads
    )
  end

  def get_project_task(project_id, id) when is_binary(project_id) and is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} ->
        Repo.one(
          from t in Task,
            where: t.id == ^id and t.project_id == ^project_id,
            preload: ^@task_api_preloads
        )

      :error ->
        nil
    end
  end

  def get_project_task(_, _), do: nil

  def last_task_id(column_id, except_id \\ nil) when is_binary(column_id) do
    base =
      from t in Task,
        where: t.column_id == ^column_id,
        order_by: [desc: t.rank],
        limit: 1,
        select: t.id

    query = if is_binary(except_id), do: from(t in base, where: t.id != ^except_id), else: base

    Repo.one(query)
  end

  @empty_doc %{"type" => "doc", "content" => []}

  @doc """
  Creates a task at the start of `column_id` (which must belong to `project_id`).
  """
  def create_task(project_id, column_id, attrs, creator_id) do
    with %Column{project_id: ^project_id} <- get_column(column_id) do
      first_rank = first_task_rank(column_id)
      rank = Rank.between(nil, first_rank)

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
      |> validate_assignee_membership(project_id)
      |> Repo.insert()
    else
      _ -> {:error, :column_not_found}
    end
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.update_changeset(attrs)
    |> validate_assignee_membership(task.project_id)
    |> Repo.update()
  end

  def delete_task(%Task{} = task), do: Repo.delete(task)

  def unassign_user_from_tasks(project_id, user_id)
      when is_binary(project_id) and is_binary(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {_count, tasks} =
      Repo.update_all(
        from(t in Task,
          where: t.project_id == ^project_id and t.assignee_id == ^user_id,
          select: t
        ),
        set: [assignee_id: nil, updated_at: now]
      )

    tasks
  end

  defp validate_assignee_membership(changeset, project_id) do
    case Ecto.Changeset.fetch_change(changeset, :assignee_id) do
      {:ok, nil} ->
        changeset

      {:ok, assignee_id} ->
        if member?(project_id, assignee_id) do
          changeset
        else
          Ecto.Changeset.add_error(changeset, :assignee_id, "не участник проекта")
        end

      :error ->
        changeset
    end
  end

  def list_task_comments(project_id) do
    Repo.all(
      from c in TaskComment,
        where: c.project_id == ^project_id,
        order_by: [asc: c.inserted_at],
        preload: [:author]
    )
  end

  def list_task_comments_for(project_id, task_id)
      when is_binary(project_id) and is_binary(task_id) do
    Repo.all(
      from c in TaskComment,
        where: c.project_id == ^project_id and c.task_id == ^task_id,
        order_by: [asc: c.inserted_at],
        preload: [:author]
    )
  end

  def get_task_comment(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get(TaskComment, id) |> Repo.preload(:author)
      :error -> nil
    end
  end

  def get_task_comment(_), do: nil

  def create_task_comment(project_id, task_id, attrs, author_id) do
    with %Task{project_id: ^project_id} <- get_task(task_id),
         {:ok, parent_id} <- resolve_comment_parent(attrs, project_id, task_id) do
      payload =
        attrs
        |> Map.new()
        |> normalize_comment_body()
        |> Map.put(:project_id, project_id)
        |> Map.put(:task_id, task_id)
        |> Map.put(:parent_id, parent_id)
        |> maybe_put_comment_author(author_id)

      %TaskComment{}
      |> TaskComment.create_changeset(payload)
      |> Repo.insert()
      |> case do
        {:ok, comment} ->
          notify_comment_recipients(comment)
          {:ok, Repo.preload(comment, :author)}

        other ->
          other
      end
    else
      {:error, _} = err -> err
      _ -> {:error, :task_not_found}
    end
  end

  defp notify_comment_recipients(%TaskComment{} = comment) do
    task = get_task(comment.task_id)

    recipients =
      [
        parent_author_agent_id(comment.parent_id),
        agent_id_if_agent(task && task.assignee_id)
        | mention_agent_ids(comment.body_doc)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == comment.author_id))
      |> Enum.uniq()

    if recipients != [] do
      slug = Repo.one(from p in Project, where: p.id == ^comment.project_id, select: p.slug)

      payload = %{
        comment_id: comment.id,
        task_id: comment.task_id,
        project_slug: slug,
        author_id: comment.author_id
      }

      AgentEvents.record_many(recipients, comment.project_id, "comment_created", payload)
    end

    :ok
  end

  defp parent_author_agent_id(nil), do: nil

  defp parent_author_agent_id(parent_id) do
    case get_task_comment(parent_id) do
      %TaskComment{author_id: author_id} -> agent_id_if_agent(author_id)
      _ -> nil
    end
  end

  defp agent_id_if_agent(nil), do: nil

  defp agent_id_if_agent(user_id) do
    Repo.one(from u in User, where: u.id == ^user_id and u.is_agent == true, select: u.id)
  end

  defp mention_agent_ids(body_doc) do
    body_doc
    |> collect_mention_ids()
    |> Enum.uniq()
    |> Enum.filter(&agent_id_if_agent/1)
  end

  defp collect_mention_ids(%{"type" => "mention"} = node) do
    case get_in(node, ["attrs", "id"]) do
      id when is_binary(id) -> [id]
      _ -> []
    end
  end

  defp collect_mention_ids(%{"content" => content}) when is_list(content) do
    Enum.flat_map(content, &collect_mention_ids/1)
  end

  defp collect_mention_ids(_), do: []

  defp normalize_comment_body(attrs) do
    case Map.get(attrs, :body_doc) || Map.get(attrs, "body_doc") do
      %{} = doc ->
        attrs
        |> Map.put(:body_doc, doc)
        |> Map.put(:body, TaskBody.to_markdown(doc))

      _ ->
        body = Map.get(attrs, :body) || Map.get(attrs, "body") || ""

        attrs
        |> Map.put(:body, body)
        |> Map.put(:body_doc, TaskBody.from_markdown(body))
    end
  end

  defp resolve_comment_parent(attrs, project_id, task_id) do
    case Map.get(attrs, :parent_id) || Map.get(attrs, "parent_id") do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      parent_id when is_binary(parent_id) ->
        case get_task_comment(parent_id) do
          %TaskComment{project_id: ^project_id, task_id: ^task_id} -> {:ok, parent_id}
          _ -> {:error, :parent_not_found}
        end

      _ ->
        {:error, :parent_not_found}
    end
  end

  def delete_task_comment(%TaskComment{} = comment), do: Repo.delete(comment)

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

  defp first_task_rank(column_id) do
    Repo.one(
      from t in Task,
        where: t.column_id == ^column_id,
        order_by: [asc: t.rank],
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

  defp maybe_put_comment_author(attrs, nil), do: attrs

  defp maybe_put_comment_author(attrs, author_id) when is_binary(author_id) do
    Map.put(attrs, :author_id, author_id)
  end
end
