defmodule Hardhat.Projects.Task do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hardhat.Accounts.User
  alias Hardhat.Projects.{Column, Project}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "tasks" do
    field :title, :string
    field :body_doc, :map, default: %{"type" => "doc", "content" => []}
    field :rank, :string

    field :start_date, :date
    field :end_date, :date

    belongs_to :project, Project
    belongs_to :column, Column
    belongs_to :creator, User
    belongs_to :assignee, User
    belongs_to :task_type, Hardhat.Projects.TaskType

    timestamps()
  end

  def create_changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :body_doc,
      :rank,
      :project_id,
      :column_id,
      :creator_id,
      :start_date,
      :end_date,
      :assignee_id,
      :task_type_id
    ])
    |> validate_required([:title, :rank, :project_id, :column_id])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_doc(:body_doc)
    |> assoc_constraint(:project)
    |> assoc_constraint(:column)
  end

  def update_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :body_doc, :start_date, :end_date, :assignee_id, :task_type_id])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_doc(:body_doc)
  end

  # Tiptap doc must be a map with `"type": "doc"`. Anything else is rejected
  # — keeps the field from accumulating malformed payloads.
  defp validate_doc(changeset, field) do
    case Ecto.Changeset.get_change(changeset, field) do
      nil ->
        changeset

      %{"type" => "doc"} ->
        changeset

      _ ->
        Ecto.Changeset.add_error(changeset, field, "must be a tiptap doc node")
    end
  end

  def move_changeset(task, attrs) do
    task
    |> cast(attrs, [:column_id, :rank])
    |> validate_required([:column_id, :rank])
    |> assoc_constraint(:column)
  end
end
