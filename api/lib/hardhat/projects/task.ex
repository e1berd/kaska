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
    field :description, :string
    field :rank, :string

    belongs_to :project, Project
    belongs_to :column, Column
    belongs_to :creator, User

    timestamps()
  end

  def create_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :rank, :project_id, :column_id, :creator_id])
    |> validate_required([:title, :rank, :project_id, :column_id])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 8000)
    |> assoc_constraint(:project)
    |> assoc_constraint(:column)
  end

  def update_changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 8000)
  end

  def move_changeset(task, attrs) do
    task
    |> cast(attrs, [:column_id, :rank])
    |> validate_required([:column_id, :rank])
    |> assoc_constraint(:column)
  end
end
