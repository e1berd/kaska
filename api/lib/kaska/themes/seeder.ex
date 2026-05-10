defmodule Kaska.Themes.Seeder do
  @moduledoc """
  Boot-time task that seeds the default theme presets. Idempotent — existing
  rows are upserted, so palette tweaks in the source ship through on next boot.
  """

  use Task, restart: :transient

  require Logger

  def start_link(_arg), do: Task.start_link(__MODULE__, :run, [])

  def run do
    Kaska.Themes.seed_defaults!()
    Logger.info("[themes] presets seeded")
    :ok
  rescue
    error ->
      Logger.warning("[themes] seed failed: #{inspect(error)}")
      :ok
  end
end
