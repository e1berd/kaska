defmodule Kaska.Projects.ProjectInvite do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "project_invites" do
    field :token, :string
    field :email, :string
    field :expires_at, :utc_datetime
    field :accepted_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :invited_by, User

    timestamps()
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:project_id, :token, :email, :invited_by_id, :expires_at, :accepted_at])
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:project_id, :token])
    |> assoc_constraint(:project)
    |> unique_constraint(:token)
  end

  defp normalize_email(nil), do: nil
  defp normalize_email(value), do: value |> to_string() |> String.downcase() |> String.trim()
end
