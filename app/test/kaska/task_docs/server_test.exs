defmodule Kaska.TaskDocs.ServerTest do
  use Kaska.DataCase

  alias Kaska.Projects.TaskDocSnapshot
  alias Kaska.TaskBody
  alias Kaska.TaskDocs
  alias Kaska.TaskDocs.Supervisor, as: TaskDocsSupervisor

  defp user_fixture do
    email = "user#{System.unique_integer([:positive])}@example.com"
    {:ok, user} = Kaska.Accounts.register_user(%{email: email, password: "correct horse battery"})
    user
  end

  defp task_fixture(body_doc) do
    owner = user_fixture()

    {:ok, project} =
      Kaska.Projects.create_project(owner.id, %{
        slug: "proj#{System.unique_integer([:positive])}",
        name: "Proj"
      })

    {_project, [todo | _], _tasks} = Kaska.Projects.board_snapshot(project.id)

    {:ok, task} =
      Kaska.Projects.create_task(project.id, todo.id, %{title: "T", body_doc: body_doc}, owner.id)

    task
  end

  defp stop_server(task_id) do
    case Registry.lookup(Kaska.TaskDocs.Registry, task_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(TaskDocsSupervisor, pid)
      [] -> :ok
    end
  end

  test "seeds a fresh task's Y.Doc from its body_doc on first join" do
    body_doc = TaskBody.from_markdown("Hello **world**")
    task = task_fixture(body_doc)

    {:ok, _pid} = TaskDocsSupervisor.lookup_or_start(task.id)
    {:ok, state_bin} = TaskDocs.Server.get_state(task.id)

    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, state_bin)
    fragment = Yex.Doc.get_xml_fragment(doc, "default")

    assert Yex.XmlFragment.length(fragment) == 1
    {:ok, paragraph} = Yex.XmlFragment.fetch(fragment, 0)
    {:ok, text} = Yex.XmlElement.fetch(paragraph, 0)
    delta = Yex.XmlText.to_delta(text)
    assert %{insert: "world", attributes: %{"bold" => true}} in delta

    assert %TaskDocSnapshot{} = Repo.get(TaskDocSnapshot, task.id)

    stop_server(task.id)
  end

  test "does not seed a task with a blank body_doc" do
    task = task_fixture(TaskBody.empty_doc())

    {:ok, _pid} = TaskDocsSupervisor.lookup_or_start(task.id)
    {:ok, state_bin} = TaskDocs.Server.get_state(task.id)

    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, state_bin)
    assert Yex.XmlFragment.length(Yex.Doc.get_xml_fragment(doc, "default")) == 0

    refute Repo.get(TaskDocSnapshot, task.id)

    stop_server(task.id)
  end

  test "never reseeds a task that already has real collaboration history" do
    task = task_fixture(TaskBody.from_markdown("From the API"))

    live_doc = Yex.Doc.new()

    Yex.Doc.get_xml_fragment(live_doc, "default")
    |> Yex.XmlFragment.push(Yex.XmlTextPrelim.from("typed live"))

    {:ok, update} = Yex.encode_state_as_update(live_doc)
    {:ok, _seq} = TaskDocs.append_update(task.id, update, nil)

    {:ok, _pid} = TaskDocsSupervisor.lookup_or_start(task.id)
    {:ok, state_bin} = TaskDocs.Server.get_state(task.id)

    doc = Yex.Doc.new()
    :ok = Yex.apply_update(doc, state_bin)
    fragment = Yex.Doc.get_xml_fragment(doc, "default")

    assert Yex.XmlFragment.length(fragment) == 1
    {:ok, text} = Yex.XmlFragment.fetch(fragment, 0)
    assert Yex.XmlText.to_string(text) == "typed live"

    stop_server(task.id)
  end
end
