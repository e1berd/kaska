defmodule Hardhat.Storage.Bootstrap do
  @moduledoc """
  Boot-time task that ensures the configured S3 bucket exists.

  RustFS may take a few seconds to come up, so we retry briefly. After
  exhausting retries we log a warning and let the supervisor continue —
  the app must boot even if the storage service is temporarily down,
  ensure_bucket is idempotent and called again on the next start.
  """

  use Task, restart: :transient

  require Logger

  @retries 12
  @sleep_ms 1_000

  def start_link(_arg), do: Task.start_link(__MODULE__, :run, [])

  def run, do: try_ensure(@retries)

  defp try_ensure(0) do
    Logger.warning("[storage] could not ensure bucket — giving up after retries")
    :ok
  end

  defp try_ensure(n) do
    case Hardhat.Storage.ensure_bucket() do
      :ok ->
        Logger.info("[storage] bucket #{Hardhat.Storage.bucket()} ready")
        :ok

      {:error, reason} ->
        Logger.debug("[storage] ensure_bucket failed (#{inspect(reason)}); retrying")
        Process.sleep(@sleep_ms)
        try_ensure(n - 1)
    end
  end
end
