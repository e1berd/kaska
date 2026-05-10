defmodule Kaska.Guardian.Token do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:jti, :string, autogenerate: false}

  schema "guardian_tokens" do
    field :aud, :string
    field :typ, :string
    field :iss, :string
    field :sub, :string
    field :exp, :integer
    field :jwt, :string
    field :claims, :map

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:jti, :aud, :typ, :iss, :sub, :exp, :jwt, :claims])
    |> validate_required([:jti, :aud, :typ, :exp, :jwt, :claims])
  end
end
