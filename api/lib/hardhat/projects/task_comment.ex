defmodule Hardhat.Projects.TaskComment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hardhat.Accounts.User
  alias Hardhat.Projects.{Project, Task}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "task_comments" do
    field :body, :string
    field :guest_name, :string
    belongs_to :task, Task
    belongs_to :project, Project
    belongs_to :author, User

    timestamps()
  end

  def create_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body, :guest_name, :task_id, :project_id, :author_id])
    |> update_change(:body, &String.trim/1)
    |> update_change(:guest_name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> validate_required([:body, :task_id, :project_id])
    |> validate_length(:body, min: 1, max: 5000)
    |> validate_length(:guest_name, max: 120)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:author_id)
  end
end
