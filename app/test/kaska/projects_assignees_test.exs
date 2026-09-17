defmodule Kaska.ProjectsAssigneesTest do
  use Kaska.DataCase, async: true

  alias Kaska.{Accounts, Projects}

  defp user_fixture do
    email = "user#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  defp assignee_ids(task), do: task |> Projects.list_task_assignees() |> Enum.map(& &1.id)

  setup do
    owner = user_fixture()
    member = user_fixture()
    outsider = user_fixture()

    {:ok, project} =
      Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    {:ok, _} = Projects.add_member(project.id, member.id)
    {_p, [todo | _], _t} = Projects.board_snapshot(project.id)

    %{owner: owner, member: member, outsider: outsider, project: project, column: todo}
  end

  test "creates a task with several assignees and the creator as author", ctx do
    {:ok, task} =
      Projects.create_task(
        ctx.project.id,
        ctx.column.id,
        %{title: "T", assignee_ids: [ctx.owner.id, ctx.member.id]},
        ctx.member.id
      )

    assert task.creator_id == ctx.member.id
    assert Enum.sort(assignee_ids(task)) == Enum.sort([ctx.owner.id, ctx.member.id])
  end

  test "replaces and clears assignees on update", ctx do
    {:ok, task} =
      Projects.create_task(
        ctx.project.id,
        ctx.column.id,
        %{title: "T", assignee_ids: [ctx.owner.id]},
        ctx.owner.id
      )

    {:ok, task} =
      Projects.update_task(Projects.get_task(task.id), %{"assignee_ids" => [ctx.member.id]})

    assert assignee_ids(Projects.get_task(task.id)) == [ctx.member.id]

    {:ok, _} = Projects.update_task(Projects.get_task(task.id), %{"assignee_ids" => []})
    assert assignee_ids(Projects.get_task(task.id)) == []
  end

  test "records who changed the task last", ctx do
    {:ok, task} = Projects.create_task(ctx.project.id, ctx.column.id, %{title: "T"}, ctx.owner.id)
    assert task.updated_by_id == ctx.owner.id

    {:ok, task} = Projects.update_task(task, %{"title" => "Renamed"}, ctx.member.id)
    assert task.updated_by_id == ctx.member.id

    {:ok, task} = Projects.update_task(task, %{"title" => "Renamed"}, ctx.owner.id)
    assert task.updated_by_id == ctx.member.id
  end

  test "rejects assignees outside the project", ctx do
    assert {:error, changeset} =
             Projects.create_task(
               ctx.project.id,
               ctx.column.id,
               %{title: "T", assignee_ids: [ctx.owner.id, ctx.outsider.id]},
               ctx.owner.id
             )

    assert %{assignee_ids: [_]} = errors_on(changeset)
  end

  test "removing a member unassigns them only", ctx do
    {:ok, task} =
      Projects.create_task(
        ctx.project.id,
        ctx.column.id,
        %{title: "T", assignee_ids: [ctx.owner.id, ctx.member.id]},
        ctx.owner.id
      )

    assert [%{id: id}] = Projects.unassign_user_from_tasks(ctx.project.id, ctx.member.id)
    assert id == task.id
    assert assignee_ids(Projects.get_task(task.id)) == [ctx.owner.id]
  end
end
