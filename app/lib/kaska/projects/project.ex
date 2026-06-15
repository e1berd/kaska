defmodule Kaska.Projects.Project do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.{Column, ProjectMember, Task}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "projects" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :avatar_key, :string
    field :background_key, :string
    field :public_link, :boolean, default: false
    field :theme_slug, :string
    field :agent_instructions, :string

    belongs_to :owner, User
    has_many :columns, Column
    has_many :tasks, Task
    has_many :members, ProjectMember

    timestamps()
  end

  @slug_format ~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/

  def create_changeset(project, attrs) do
    project
    |> cast(attrs, [:slug, :name, :description, :owner_id])
    |> update_change(:slug, &normalize_slug/1)
    |> validate_required([:slug, :name, :owner_id])
    |> validate_length(:slug, min: 2, max: 64)
    |> validate_format(:slug, @slug_format,
      message: "только латиница, цифры и дефис; не на краях"
    )
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:description, max: 4000)
    |> assoc_constraint(:owner)
    |> unique_constraint(:slug)
  end

  def update_changeset(project, attrs) do
    project
    |> cast(attrs, [:name, :description, :agent_instructions])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:description, max: 4000)
    |> validate_length(:agent_instructions, max: 8000)
  end

  def visibility_changeset(project, attrs) do
    project
    |> cast(attrs, [:public_link])
    |> validate_required([:public_link])
  end

  def theme_changeset(project, attrs) do
    project
    |> cast(attrs, [:theme_slug])
    |> validate_length(:theme_slug, min: 2, max: 64)
  end

  def media_changeset(project, attrs) do
    project
    |> cast(attrs, [:avatar_key, :background_key])
    |> validate_length(:avatar_key, max: 512)
    |> validate_length(:background_key, max: 512)
  end

  defp normalize_slug(nil), do: nil
  defp normalize_slug(value), do: value |> to_string() |> String.downcase() |> String.trim()
end
