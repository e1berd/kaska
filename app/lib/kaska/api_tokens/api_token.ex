defmodule Kaska.ApiTokens.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :last_four, :string
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :user, User

    timestamps()
  end

  def create_changeset(token, attrs) do
    token
    |> cast(attrs, [:name])
    |> update_change(:name, fn
      nil -> nil
      name -> String.trim(name)
    end)
    |> validate_required([:name, :token_hash, :last_four, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:token_hash)
    |> assoc_constraint(:user)
  end
end
