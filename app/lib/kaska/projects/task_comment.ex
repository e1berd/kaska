defmodule Kaska.Projects.TaskComment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.{Project, Task, TaskComment}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "task_comments" do
    field :body, :string
    field :body_doc, :map, default: %{"type" => "doc", "content" => []}
    field :guest_name, :string
    belongs_to :task, Task
    belongs_to :project, Project
    belongs_to :author, User
    belongs_to :parent, TaskComment
    has_many :replies, TaskComment, foreign_key: :parent_id

    timestamps()
  end

  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body, :body_doc, :guest_name, :task_id, :project_id, :author_id, :parent_id])
    |> update_change(:body, &String.trim/1)
    |> update_change(:guest_name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> validate_required([:body, :body_doc, :task_id, :project_id])
    |> validate_length(:body, min: 1, max: 5000)
    |> validate_length(:guest_name, max: 120)
    |> validate_doc(:body_doc)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:author_id)
    |> foreign_key_constraint(:parent_id)
  end

  defp validate_doc(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      %{"type" => "doc"} -> changeset
      _ -> add_error(changeset, field, "must be a tiptap doc node")
    end
  end
end
