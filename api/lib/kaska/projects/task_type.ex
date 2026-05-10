defmodule Kaska.Projects.TaskType do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "task_types" do
    field :name, :string
    field :color, :string, default: "gray"
    field :text_color, :string, default: "white"
    field :description, :string

    belongs_to :project, Project

    timestamps()
  end

  def changeset(task_type, attrs) do
    task_type
    |> cast(attrs, [:name, :description, :color, :text_color, :project_id])
    |> update_change(:name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> update_change(:description, fn
      nil ->
        nil

      desc ->
        trimmed = String.trim(desc)
        if trimmed == "", do: nil, else: trimmed
    end)
    |> validate_required([:name, :color, :text_color, :project_id])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:description, max: 1000)
    |> assoc_constraint(:project)
  end
end
