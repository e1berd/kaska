defmodule Kaska.Projects.ProjectThemePref do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "project_theme_prefs" do
    field :theme_slug, :string

    belongs_to :project, Project
    belongs_to :user, User

    timestamps()
  end

  def changeset(pref, attrs) do
    pref
    |> cast(attrs, [:project_id, :user_id, :theme_slug])
    |> validate_required([:project_id, :user_id, :theme_slug])
    |> validate_length(:theme_slug, min: 2, max: 64)
    |> assoc_constraint(:project)
    |> assoc_constraint(:user)
    |> unique_constraint([:project_id, :user_id])
  end
end
