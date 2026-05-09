defmodule Hardhat.Themes do
  @moduledoc """
  Theme presets. Each theme has a paired light/dark palette covering all
  Vuetify role colors (primary/secondary/tertiary + surface tones + error +
  outlines + inverses). Surface tones are shared across all themes (M3
  baseline), only the seed-driven roles vary.

  The frontend pulls themes lazily by slug — only metadata (`{slug, name}`)
  ships in `list_index/0`. `get/1` returns the full palette.
  """

  alias Hardhat.Repo
  alias Hardhat.Themes.Theme

  import Ecto.Query

  def list_index do
    Repo.all(from t in Theme, order_by: [asc: t.inserted_at], select: %{slug: t.slug, name: t.name})
  end

  def get_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Theme, slug: slug)
  end

  def get_by_slug(_), do: nil

  def default_slug, do: "hardhat"

  def seed_defaults! do
    for {slug, name, light_roles, dark_roles} <- presets() do
      attrs = %{
        slug: slug,
        name: name,
        palette_light: Map.merge(light_neutrals(), light_roles),
        palette_dark: Map.merge(dark_neutrals(), dark_roles)
      }

      Repo.insert(
        Theme.changeset(%Theme{}, attrs),
        on_conflict: {:replace, [:name, :palette_light, :palette_dark, :updated_at]},
        conflict_target: :slug
      )
    end

    :ok
  end

  defp presets do
    [
      {"hardhat", "HardHat",
       %{
         "primary" => "#6750A4",
         "on-primary" => "#FFFFFF",
         "primary-container" => "#EADDFF",
         "on-primary-container" => "#21005D",
         "secondary" => "#625B71",
         "on-secondary" => "#FFFFFF",
         "secondary-container" => "#E8DEF8",
         "on-secondary-container" => "#1D192B",
         "tertiary" => "#7D5260",
         "on-tertiary" => "#FFFFFF",
         "tertiary-container" => "#FFD8E4",
         "on-tertiary-container" => "#31111D",
         "inverse-primary" => "#D0BCFF"
       },
       %{
         "primary" => "#D0BCFF",
         "on-primary" => "#381E72",
         "primary-container" => "#4F378B",
         "on-primary-container" => "#EADDFF",
         "secondary" => "#CCC2DC",
         "on-secondary" => "#332D41",
         "secondary-container" => "#4A4458",
         "on-secondary-container" => "#E8DEF8",
         "tertiary" => "#EFB8C8",
         "on-tertiary" => "#492532",
         "tertiary-container" => "#633B48",
         "on-tertiary-container" => "#FFD8E4",
         "inverse-primary" => "#6750A4"
       }},
      {"indigo", "Индиго",
       %{
         "primary" => "#3F4DCB",
         "on-primary" => "#FFFFFF",
         "primary-container" => "#DEE0FF",
         "on-primary-container" => "#00006E",
         "secondary" => "#5B5D72",
         "on-secondary" => "#FFFFFF",
         "secondary-container" => "#E0E1F9",
         "on-secondary-container" => "#181A2C",
         "tertiary" => "#77536D",
         "on-tertiary" => "#FFFFFF",
         "tertiary-container" => "#FFD7F0",
         "on-tertiary-container" => "#2D1127",
         "inverse-primary" => "#BEC2FF"
       },
       %{
         "primary" => "#BEC2FF",
         "on-primary" => "#06149E",
         "primary-container" => "#2532B4",
         "on-primary-container" => "#DEE0FF",
         "secondary" => "#C4C5DD",
         "on-secondary" => "#2D2F42",
         "secondary-container" => "#444559",
         "on-secondary-container" => "#E0E1F9",
         "tertiary" => "#E5BAD5",
         "on-tertiary" => "#44263C",
         "tertiary-container" => "#5D3C54",
         "on-tertiary-container" => "#FFD7F0",
         "inverse-primary" => "#3F4DCB"
       }},
      {"forest", "Лес",
       %{
         "primary" => "#3D6A1E",
         "on-primary" => "#FFFFFF",
         "primary-container" => "#BCF295",
         "on-primary-container" => "#0A2000",
         "secondary" => "#56624A",
         "on-secondary" => "#FFFFFF",
         "secondary-container" => "#DAE7C8",
         "on-secondary-container" => "#141F0D",
         "tertiary" => "#386666",
         "on-tertiary" => "#FFFFFF",
         "tertiary-container" => "#BCECEB",
         "on-tertiary-container" => "#002020",
         "inverse-primary" => "#A2D67C"
       },
       %{
         "primary" => "#A2D67C",
         "on-primary" => "#143800",
         "primary-container" => "#265109",
         "on-primary-container" => "#BCF295",
         "secondary" => "#BECBAD",
         "on-secondary" => "#283420",
         "secondary-container" => "#3E4A34",
         "on-secondary-container" => "#DAE7C8",
         "tertiary" => "#A0CFCF",
         "on-tertiary" => "#003737",
         "tertiary-container" => "#1F4E4E",
         "on-tertiary-container" => "#BCECEB",
         "inverse-primary" => "#3D6A1E"
       }},
      {"ocean", "Океан",
       %{
         "primary" => "#00658F",
         "on-primary" => "#FFFFFF",
         "primary-container" => "#C6E7FF",
         "on-primary-container" => "#001E2E",
         "secondary" => "#4F616E",
         "on-secondary" => "#FFFFFF",
         "secondary-container" => "#D2E5F5",
         "on-secondary-container" => "#0B1D29",
         "tertiary" => "#615A7D",
         "on-tertiary" => "#FFFFFF",
         "tertiary-container" => "#E7DEFF",
         "on-tertiary-container" => "#1D1837",
         "inverse-primary" => "#86CEFF"
       },
       %{
         "primary" => "#86CEFF",
         "on-primary" => "#00344C",
         "primary-container" => "#004C6C",
         "on-primary-container" => "#C6E7FF",
         "secondary" => "#B7C9D8",
         "on-secondary" => "#22333E",
         "secondary-container" => "#384956",
         "on-secondary-container" => "#D2E5F5",
         "tertiary" => "#CBC2EA",
         "on-tertiary" => "#322D4D",
         "tertiary-container" => "#494264",
         "on-tertiary-container" => "#E7DEFF",
         "inverse-primary" => "#00658F"
       }},
      {"crimson", "Малиновый",
       %{
         "primary" => "#B12544",
         "on-primary" => "#FFFFFF",
         "primary-container" => "#FFD9DC",
         "on-primary-container" => "#400010",
         "secondary" => "#765659",
         "on-secondary" => "#FFFFFF",
         "secondary-container" => "#FFD9DC",
         "on-secondary-container" => "#2C1518",
         "tertiary" => "#785830",
         "on-tertiary" => "#FFFFFF",
         "tertiary-container" => "#FFDDB6",
         "on-tertiary-container" => "#2A1700",
         "inverse-primary" => "#FFB3B7"
       },
       %{
         "primary" => "#FFB3B7",
         "on-primary" => "#5F1124",
         "primary-container" => "#8E0B33",
         "on-primary-container" => "#FFD9DC",
         "secondary" => "#E5BDC0",
         "on-secondary" => "#44292C",
         "secondary-container" => "#5D3F42",
         "on-secondary-container" => "#FFD9DC",
         "tertiary" => "#E9C08C",
         "on-tertiary" => "#432C04",
         "tertiary-container" => "#5D4119",
         "on-tertiary-container" => "#FFDDB6",
         "inverse-primary" => "#B12544"
       }},
      {"mocha", "Мокко",
       %{
         "primary" => "#7F551A",
         "on-primary" => "#FFFFFF",
         "primary-container" => "#FFDCB8",
         "on-primary-container" => "#2C1700",
         "secondary" => "#705B40",
         "on-secondary" => "#FFFFFF",
         "secondary-container" => "#FCDFBC",
         "on-secondary-container" => "#281906",
         "tertiary" => "#566249",
         "on-tertiary" => "#FFFFFF",
         "tertiary-container" => "#D9E7C7",
         "on-tertiary-container" => "#141E0B",
         "inverse-primary" => "#F4BB73"
       },
       %{
         "primary" => "#F4BB73",
         "on-primary" => "#482900",
         "primary-container" => "#653D03",
         "on-primary-container" => "#FFDCB8",
         "secondary" => "#DEC2A0",
         "on-secondary" => "#3F2D16",
         "secondary-container" => "#574329",
         "on-secondary-container" => "#FCDFBC",
         "tertiary" => "#BDCBAC",
         "on-tertiary" => "#28341E",
         "tertiary-container" => "#3E4A33",
         "on-tertiary-container" => "#D9E7C7",
         "inverse-primary" => "#7F551A"
       }}
    ]
  end

  defp light_neutrals do
    %{
      "background" => "#FFFBFE",
      "on-background" => "#1C1B1F",
      "surface" => "#FFFBFE",
      "on-surface" => "#1C1B1F",
      "surface-variant" => "#E7E0EC",
      "on-surface-variant" => "#49454F",
      "surface-container-lowest" => "#FFFFFF",
      "surface-container-low" => "#F7F2FA",
      "surface-container" => "#F3EDF7",
      "surface-container-high" => "#ECE6F0",
      "surface-container-highest" => "#E6E0E9",
      "error" => "#B3261E",
      "on-error" => "#FFFFFF",
      "error-container" => "#F9DEDC",
      "on-error-container" => "#410E0B",
      "outline" => "#79747E",
      "outline-variant" => "#CAC4D0",
      "shadow" => "#000000",
      "scrim" => "#000000",
      "inverse-surface" => "#313033",
      "inverse-on-surface" => "#F4EFF4"
    }
  end

  defp dark_neutrals do
    %{
      "background" => "#1C1B1F",
      "on-background" => "#E6E1E5",
      "surface" => "#1C1B1F",
      "on-surface" => "#E6E1E5",
      "surface-variant" => "#49454F",
      "on-surface-variant" => "#CAC4D0",
      "surface-container-lowest" => "#0F0D13",
      "surface-container-low" => "#1D1B20",
      "surface-container" => "#211F26",
      "surface-container-high" => "#2B2930",
      "surface-container-highest" => "#36343B",
      "error" => "#F2B8B5",
      "on-error" => "#601410",
      "error-container" => "#8C1D18",
      "on-error-container" => "#F9DEDC",
      "outline" => "#938F99",
      "outline-variant" => "#49454F",
      "shadow" => "#000000",
      "scrim" => "#000000",
      "inverse-surface" => "#E6E1E5",
      "inverse-on-surface" => "#313033"
    }
  end
end
