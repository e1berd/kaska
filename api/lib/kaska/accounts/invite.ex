defmodule Kaska.Accounts.Invite do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "invites" do
    field :token, :string
    field :email, :string
    field :expires_at, :utc_datetime

    timestamps()
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:token, :email, :expires_at])
    |> validate_required([:token])
    |> unique_constraint(:token)
  end
end
