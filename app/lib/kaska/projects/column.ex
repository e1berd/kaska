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
    field :description, :string
    field :color, :string, default: "#E8DEF8"

    belongs_to :project, Project
    has_many :tasks, Task

    timestamps()
  end

  def create_changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :rank, :project_id, :description, :color])
    |> validate_required([:name, :rank, :project_id, :color])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:description, max: 2000)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/)
    |> assoc_constraint(:project)
  end

  def rename_changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :description, :color])
    |> validate_required([:name, :color])
    |> validate_length(:name, min: 1, max: 64)
    |> validate_length(:description, max: 2000)
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/)
  end

  def rank_changeset(column, attrs) do
    column
    |> cast(attrs, [:rank])
    |> validate_required([:rank])
  end
end
