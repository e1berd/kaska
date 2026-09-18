defmodule Kaska.TaskHistoryTest do
  use Kaska.DataCase, async: true

  alias Kaska.{Accounts, Projects}
  alias Kaska.Projects.TaskHistoryEvent

  defp user_fixture do
    email = "user#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  defp events_for(task_id) do
    Kaska.Repo.all(
      Ecto.Query.from(e in TaskHistoryEvent,
        where: e.task_id == ^task_id,
        order_by: [asc: e.inserted_at]
      )
    )
  end

  setup do
    owner = user_fixture()

    {:ok, project} =
      Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    {_p, [todo, in_progress, done], _t} = Projects.board_snapshot(project.id)

    %{owner: owner, project: project, todo: todo, in_progress: in_progress, done: done}
  end

  test "create_task records a single created event", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    assert [event] = events_for(task.id)
    assert event.kind == "created"
    assert event.field == nil
    assert event.actor_id == ctx.owner.id
    assert [%TaskHistoryEvent{kind: "created"}] = task.history_events
  end

  test "update_task records one field_changed event per changed field, batched together", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, updated} =
      Projects.update_task(
        Projects.get_task(task.id),
        %{"title" => "New title", "end_date" => ~D[2026-09-30]},
        ctx.owner.id
      )

    events = events_for(updated.id)
    diffs = Enum.filter(events, &(&1.kind == "field_changed"))

    assert length(diffs) == 2
    assert Enum.all?(diffs, &(&1.batch_id == hd(diffs).batch_id))
    assert length(updated.history_events) == 2

    title_event = Enum.find(diffs, &(&1.field == "title"))
    assert title_event.old_value == %{"v" => "T"}
    assert title_event.new_value == %{"v" => "New title"}
  end

  test "update_task with no real change records nothing new", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)
    before_count = length(events_for(task.id))

    {:ok, _same} =
      Projects.update_task(Projects.get_task(task.id), %{"title" => "T"}, ctx.owner.id)

    assert length(events_for(task.id)) == before_count
  end

  test "move_task records a column_moved event", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, moved} =
      Projects.move_task(Projects.get_task(task.id), ctx.in_progress.id, nil, nil, ctx.owner.id)

    assert [_created, move_event] = events_for(moved.id)
    assert move_event.kind == "column_moved"
    assert move_event.old_value == %{"v" => ctx.todo.id}
    assert move_event.new_value == %{"v" => ctx.in_progress.id}
  end

  test "a task's first move is never a regression, even backward across columns", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.done.id, %{title: "T"}, ctx.owner.id)

    {:ok, moved} =
      Projects.move_task(Projects.get_task(task.id), ctx.in_progress.id, nil, nil, ctx.owner.id)

    assert [_created, move_event] = events_for(moved.id)
    refute move_event.regression
  end

  test "moving forward is never a regression", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, moved} =
      Projects.move_task(Projects.get_task(task.id), ctx.in_progress.id, nil, nil, ctx.owner.id)

    assert [_created, move_event] = events_for(moved.id)
    refute move_event.regression
  end

  test "moving backward after a real forward move is flagged as a regression", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, task} =
      Projects.move_task(Projects.get_task(task.id), ctx.done.id, nil, nil, ctx.owner.id)

    {:ok, task} =
      Projects.move_task(Projects.get_task(task.id), ctx.in_progress.id, nil, nil, ctx.owner.id)

    [_created, _forward, backward_event] = events_for(task.id)
    assert backward_event.regression

    {:ok, _task} =
      Projects.move_task(Projects.get_task(task.id), ctx.done.id, nil, nil, ctx.owner.id)

    [_, _, _, forward_again] = events_for(task.id)
    refute forward_again.regression
  end

  test "reverting a field change restores the old value and links back", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, _} =
      Projects.update_task(Projects.get_task(task.id), %{"title" => "Changed"}, ctx.owner.id)

    [_created, change_event] = events_for(task.id)

    {:ok, reverted_task} =
      Projects.revert_task_history_event(change_event, ctx.owner.id, "нашёл баги, откатываю")

    assert reverted_task.title == "T"

    [_created, _change, revert_event] = events_for(task.id)
    assert revert_event.reverts_event_id == change_event.id
    assert revert_event.comment == "нашёл баги, откатываю"
    assert revert_event.new_value == %{"v" => "T"}
  end

  test "reverting a column move puts the task back in its previous column", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, moved} =
      Projects.move_task(Projects.get_task(task.id), ctx.done.id, nil, nil, ctx.owner.id)

    [_created, move_event] = events_for(moved.id)

    {:ok, reverted_task} = Projects.revert_task_history_event(move_event, ctx.owner.id)

    assert reverted_task.column_id == ctx.todo.id
  end

  test "reverting a description (body_doc) change is rejected", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    doc = %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}

    {:ok, _} =
      Projects.update_task(Projects.get_task(task.id), %{"body_doc" => doc}, ctx.owner.id)

    [_created, doc_event] = events_for(task.id)
    assert doc_event.field == "body_doc"

    assert Projects.revert_task_history_event(doc_event, ctx.owner.id) ==
             {:error, :not_revertible}
  end

  test "rolling back to an earlier point undoes every later change, converging on that state",
       ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, _} =
      Projects.update_task(Projects.get_task(task.id), %{"title" => "First edit"}, ctx.owner.id)

    [_created, anchor_event] = events_for(task.id)

    {:ok, _} =
      Projects.update_task(Projects.get_task(task.id), %{"title" => "Second edit"}, ctx.owner.id)

    {:ok, _} = Projects.move_task(Projects.get_task(task.id), ctx.done.id, nil, nil, ctx.owner.id)

    {:ok, final_task} =
      Projects.rollback_task_history_event(anchor_event, ctx.owner.id, "неправильно, откатываю")

    assert final_task.title == "First edit"
    assert final_task.column_id == ctx.todo.id

    revert_events =
      task.id
      |> events_for()
      |> Enum.filter(&(&1.reverts_event_id != nil))

    assert length(revert_events) == 2
    assert Enum.all?(revert_events, &(&1.batch_id == hd(revert_events).batch_id))
    assert Enum.all?(revert_events, &(&1.comment == "неправильно, откатываю"))
    assert length(final_task.history_events) == 2
  end

  test "rolling back skips a non-revertible description change instead of failing entirely",
       ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)

    {:ok, _} =
      Projects.update_task(Projects.get_task(task.id), %{"title" => "First edit"}, ctx.owner.id)

    [_created, anchor_event] = events_for(task.id)

    doc = %{"type" => "doc", "content" => [%{"type" => "paragraph"}]}

    {:ok, _} =
      Projects.update_task(Projects.get_task(task.id), %{"body_doc" => doc}, ctx.owner.id)

    {:ok, _} =
      Projects.update_task(Projects.get_task(task.id), %{"title" => "Second edit"}, ctx.owner.id)

    {:ok, final_task} = Projects.rollback_task_history_event(anchor_event, ctx.owner.id)

    assert final_task.title == "First edit"
    assert final_task.body_doc == doc
  end

  test "list_task_history returns newest first and paginates with `before`", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.todo.id, %{title: "T"}, ctx.owner.id)
    {:ok, _} = Projects.update_task(Projects.get_task(task.id), %{"title" => "A"}, ctx.owner.id)
    {:ok, _} = Projects.update_task(Projects.get_task(task.id), %{"title" => "B"}, ctx.owner.id)

    [newest, middle, _oldest] = Projects.list_task_history(ctx.project.id, limit: 3)

    assert newest.inserted_at >= middle.inserted_at

    older = Projects.list_task_history(ctx.project.id, before: newest.inserted_at)
    refute Enum.any?(older, &(&1.id == newest.id))
  end
end
