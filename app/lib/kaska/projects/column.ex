defmodule Kaska.Projects.Column do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Projects.{Project, Task}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "columns" do
    field :name, :string
    field :rank, :string

    belongs_to :project, Project
    has_many :tasks, Task

    timestamps()
  end

  def create_changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :rank, :project_id])
    |> validate_required([:name, :rank, :project_id])
    |> validate_length(:name, min: 1, max: 64)
    |> assoc_constraint(:project)
  end

  def rename_changeset(column, attrs) do
    column
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 64)
  end

  def rank_changeset(column, attrs) do
    column
    |> cast(attrs, [:rank])
    |> validate_required([:rank])
  end
end
