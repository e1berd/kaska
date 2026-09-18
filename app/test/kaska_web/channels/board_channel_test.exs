defmodule KaskaWeb.BoardChannelTest do
  use KaskaWeb.ChannelCase, async: true

  alias Kaska.{Accounts, Projects}

  defp user_fixture do
    email = "user#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  defp user_socket(user), do: socket(KaskaWeb.UserSocket, nil, %{current_user: user})

  setup do
    owner = user_fixture()

    {:ok, project} =
      Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    {_p, [todo, in_progress, _done], _t} = Projects.board_snapshot(project.id)

    {:ok, _reply, socket} =
      owner |> user_socket() |> subscribe_and_join(KaskaWeb.BoardChannel, "board:#{project.id}")

    %{owner: owner, project: project, todo: todo, in_progress: in_progress, socket: socket}
  end

  test "create_task, update_task and move_task each broadcast their history batch", ctx do
    ref = push(ctx.socket, "create_task", %{"column_id" => ctx.todo.id, "title" => "T"})
    assert_reply ref, :ok, %{id: task_id}
    assert_broadcast "task_history_events_created", %{events: [%{kind: "created"}]}

    ref = push(ctx.socket, "update_task", %{"id" => task_id, "title" => "Changed"})
    assert_reply ref, :ok, _

    assert_broadcast "task_history_events_created", %{
      events: [%{kind: "field_changed", field: "title"}]
    }

    ref = push(ctx.socket, "move_task", %{"id" => task_id, "column_id" => ctx.in_progress.id})
    assert_reply ref, :ok, _
    assert_broadcast "task_history_events_created", %{events: [%{kind: "column_moved"}]}
  end

  test "list_task_history replies with the project's events, newest first", ctx do
    ref = push(ctx.socket, "create_task", %{"column_id" => ctx.todo.id, "title" => "T"})
    assert_reply ref, :ok, %{id: task_id}
    ref = push(ctx.socket, "update_task", %{"id" => task_id, "title" => "Changed"})
    assert_reply ref, :ok, _

    ref = push(ctx.socket, "list_task_history", %{})
    assert_reply ref, :ok, %{events: [%{kind: "field_changed"}, %{kind: "created"}]}
  end

  test "revert_task_history_event undoes the change and carries the comment", ctx do
    ref = push(ctx.socket, "create_task", %{"column_id" => ctx.todo.id, "title" => "T"})
    assert_reply ref, :ok, %{id: task_id}
    ref = push(ctx.socket, "update_task", %{"id" => task_id, "title" => "Changed"})
    assert_reply ref, :ok, _

    ref = push(ctx.socket, "list_task_history", %{})
    assert_reply ref, :ok, %{events: [change_event, _created]}

    ref =
      push(ctx.socket, "revert_task_history_event", %{
        "id" => change_event.id,
        "comment" => "нашёл баги"
      })

    assert_reply ref, :ok, %{title: "T"}
    assert_broadcast "task_updated", %{title: "T"}

    assert_broadcast "task_history_events_created", %{
      events: [%{reverts_event_id: reverts_id, comment: "нашёл баги"}]
    }

    assert reverts_id == change_event.id
  end

  test "revert_task_history_event rejects an event from another project", ctx do
    other_owner = user_fixture()

    {:ok, other_project} =
      Projects.create_project(other_owner.id, %{
        slug: "other#{System.unique_integer([:positive])}",
        name: "Other"
      })

    {_p, [other_todo | _], _t} = Projects.board_snapshot(other_project.id)

    {:ok, _other_task} =
      Projects.create_task(other_project.id, other_todo.id, %{title: "T"}, other_owner.id)

    [other_event] = Projects.list_task_history(other_project.id)

    ref = push(ctx.socket, "revert_task_history_event", %{"id" => other_event.id})
    assert_reply ref, :error, %{message: "history_event_not_found"}
  end

  test "rollback_task_history_event undoes every later change in one batch", ctx do
    ref = push(ctx.socket, "create_task", %{"column_id" => ctx.todo.id, "title" => "T"})
    assert_reply ref, :ok, %{id: task_id}
    assert_broadcast "task_history_events_created", _

    ref = push(ctx.socket, "update_task", %{"id" => task_id, "title" => "First"})
    assert_reply ref, :ok, _
    assert_broadcast "task_history_events_created", _
    ref = push(ctx.socket, "list_task_history", %{})
    assert_reply ref, :ok, %{events: [anchor_event | _]}

    ref = push(ctx.socket, "update_task", %{"id" => task_id, "title" => "Second"})
    assert_reply ref, :ok, _
    assert_broadcast "task_history_events_created", _
    ref = push(ctx.socket, "move_task", %{"id" => task_id, "column_id" => ctx.in_progress.id})
    assert_reply ref, :ok, _
    assert_broadcast "task_history_events_created", _

    ref =
      push(ctx.socket, "rollback_task_history_event", %{
        "id" => anchor_event.id,
        "comment" => "откатываю"
      })

    assert_reply ref, :ok, %{title: "First", column_id: todo_id}
    assert todo_id == ctx.todo.id

    assert_broadcast "task_updated", %{title: "First"}
    assert_broadcast "task_moved", %{title: "First"}

    assert_broadcast "task_history_events_created", %{events: events}
    assert length(events) == 2
    assert Enum.all?(events, &(&1.comment == "откатываю"))
  end
end
