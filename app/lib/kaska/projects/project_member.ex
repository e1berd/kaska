defmodule Kaska.Projects.ProjectMember do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "project_members" do
    field :role, Ecto.Enum, values: [:owner, :member], default: :member

    belongs_to :project, Project
    belongs_to :user, User

    timestamps()
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:project_id, :user_id, :role])
    |> validate_required([:project_id, :user_id, :role])
    |> assoc_constraint(:project)
    |> assoc_constraint(:user)
    |> unique_constraint([:project_id, :user_id])
  end
end
