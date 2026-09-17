defmodule Kaska.AgentRuntime.AgentConfig do
  @moduledoc """
  Runtime settings of an agent (1:1 with a bot `User`): whether it may work
  with code in a supervisor container, which LLM provider it talks to and the
  encrypted API key. The plaintext key is write-only: it is never rendered back.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.AgentRuntime.Presets

  @kinds ~w(chat_only code_capable)
  @provider_kinds ~w(anthropic openai_compatible ollama_local)

  @primary_key false
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "agent_configs" do
    belongs_to :agent, User, primary_key: true

    field :kind, :string, default: "chat_only"
    field :provider_kind, :string
    field :provider_preset, :string
    field :base_url, :string
    field :model, :string
    field :encrypted_api_key, Kaska.Encrypted.Binary, redact: true
    field :api_key, :string, virtual: true, redact: true
    field :system_prompt, :string
    field :auto_run_enabled, :boolean, default: false

    timestamps()
  end

  def kinds, do: @kinds
  def provider_kinds, do: @provider_kinds

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :kind,
      :provider_kind,
      :provider_preset,
      :base_url,
      :model,
      :api_key,
      :system_prompt,
      :auto_run_enabled
    ])
    |> update_change(:base_url, &blank_to_nil/1)
    |> update_change(:model, &blank_to_nil/1)
    |> update_change(:system_prompt, &blank_to_nil/1)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:provider_kind, @provider_kinds)
    |> validate_inclusion(:provider_preset, Presets.slugs())
    |> apply_preset_defaults()
    |> validate_length(:base_url, max: 512)
    |> validate_format(:base_url, ~r{\Ahttps?://}, message: "must be an http(s) URL")
    |> validate_length(:model, max: 200)
    |> validate_length(:system_prompt, max: 20_000)
    |> put_api_key()
    |> validate_code_capable()
  end

  defp apply_preset_defaults(changeset) do
    case Presets.get(get_change(changeset, :provider_preset)) do
      nil ->
        changeset

      preset ->
        changeset
        |> put_change(:provider_kind, preset.provider_kind)
        |> put_default_base_url(preset.base_url)
    end
  end

  defp put_default_base_url(changeset, nil), do: changeset

  defp put_default_base_url(changeset, default) do
    if get_field(changeset, :base_url),
      do: changeset,
      else: put_change(changeset, :base_url, default)
  end

  defp put_api_key(changeset) do
    case fetch_change(changeset, :api_key) do
      {:ok, key} -> put_change(changeset, :encrypted_api_key, blank_to_nil(key))
      :error -> changeset
    end
  end

  defp validate_code_capable(changeset) do
    if get_field(changeset, :kind) == "code_capable" do
      changeset
      |> validate_required([:provider_kind, :model])
      |> validate_provider_requirements()
    else
      changeset
    end
  end

  defp validate_provider_requirements(changeset) do
    case get_field(changeset, :provider_kind) do
      "anthropic" ->
        require_api_key(changeset)

      "openai_compatible" ->
        changeset |> validate_required([:base_url]) |> require_hosted_api_key()

      "ollama_local" ->
        validate_required(changeset, [:base_url])

      _ ->
        changeset
    end
  end

  defp require_hosted_api_key(changeset) do
    if get_field(changeset, :provider_preset) == "lm_studio",
      do: changeset,
      else: require_api_key(changeset)
  end

  defp require_api_key(changeset) do
    if get_field(changeset, :encrypted_api_key) do
      changeset
    else
      add_error(changeset, :api_key, "can't be blank")
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
