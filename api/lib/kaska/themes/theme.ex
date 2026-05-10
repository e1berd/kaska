defmodule Kaska.Themes.Theme do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "themes" do
    field :slug, :string
    field :name, :string
    field :palette_light, :map
    field :palette_dark, :map

    timestamps()
  end

  def changeset(theme, attrs) do
    theme
    |> cast(attrs, [:slug, :name, :palette_light, :palette_dark])
    |> validate_required([:slug, :name, :palette_light, :palette_dark])
    |> validate_length(:slug, min: 2, max: 64)
    |> validate_format(:slug, ~r/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/)
    |> unique_constraint(:slug)
  end
end
