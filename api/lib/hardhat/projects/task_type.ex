defmodule Hardhat.Projects.TaskType do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hardhat.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "task_types" do
    field :name, :string
    field :color, :string, default: "gray"

    belongs_to :project, Project

    timestamps()
  end

  def changeset(task_type, attrs) do
    task_type
    |> cast(attrs, [:name, :color, :project_id])
    |> validate_required([:name, :color, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> assoc_constraint(:project)
  end
end
