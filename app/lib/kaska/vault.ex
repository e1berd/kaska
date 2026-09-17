defmodule Kaska.Vault do
  @moduledoc """
  Encryption-at-rest for secrets stored in the database (agent LLM API keys).

  The AES-256-GCM key comes from `:kaska, Kaska.Vault, :key` (32 raw bytes),
  set from the base64 `AGENT_SECRETS_KEY` env var in `config/runtime.exs`.
  Rotating the key requires adding the old one as a retired cipher.
  """

  use Cloak.Vault, otp_app: :kaska

  @impl GenServer
  def init(config) do
    ciphers = [
      default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: key!(), iv_length: 12}
    ]

    {:ok, Keyword.put(config, :ciphers, ciphers)}
  end

  defp key! do
    case Application.fetch_env!(:kaska, __MODULE__)[:key] do
      <<_::binary-size(32)>> = key -> key
      _ -> raise "Kaska.Vault key must be exactly 32 bytes"
    end
  end
end
