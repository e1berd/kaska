defmodule Kaska.AgentRuntime.AgentConfig do
  @moduledoc """
  Runtime settings of an agent (1:1 with a bot `User`): the LLM provider it
  talks to, the model and the encrypted credential. The plaintext credential is
  write-only: only whether it is set and its last characters are shown.

  `auth_method` says what the credential is: a provider API key, or — for
  Anthropic only — a Claude subscription OAuth token from `claude setup-token`.
  Changing the method drops the stored credential unless a new one is given.

  A config may be saved incomplete; `missing/1` lists what still blocks a run.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.AgentRuntime.Presets

  @provider_kinds ~w(anthropic openai_compatible ollama_local)
  @keyless_presets ~w(lm_studio ollama)
  @auth_methods ~w(api_key subscription)
  @visible_key_chars 4

  @primary_key false
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "agent_configs" do
    belongs_to :agent, User, primary_key: true

    field :provider_kind, :string
    field :provider_preset, :string
    field :auth_method, :string, default: "api_key"
    field :base_url, :string
    field :model, :string
    field :encrypted_api_key, Kaska.Encrypted.Binary, redact: true
    field :api_key, :string, virtual: true, redact: true
    field :system_prompt, :string
    field :auto_run_enabled, :boolean, default: false

    timestamps()
  end

  def provider_kinds, do: @provider_kinds

  def auth_methods, do: @auth_methods

  def changeset(config, attrs) do
    config
    |> cast(attrs, [
      :provider_kind,
      :provider_preset,
      :auth_method,
      :base_url,
      :model,
      :api_key,
      :system_prompt,
      :auto_run_enabled
    ])
    |> update_change(:base_url, &blank_to_nil/1)
    |> update_change(:model, &blank_to_nil/1)
    |> update_change(:system_prompt, &blank_to_nil/1)
    |> validate_inclusion(:provider_kind, @provider_kinds)
    |> validate_inclusion(:provider_preset, Presets.slugs())
    |> validate_inclusion(:auth_method, @auth_methods)
    |> apply_preset()
    |> put_api_key_auth_for_non_anthropic()
    |> validate_length(:base_url, max: 512)
    |> validate_format(:base_url, ~r{\Ahttps?://}, message: "must be an http(s) URL")
    |> validate_length(:model, max: 200)
    |> validate_length(:system_prompt, max: 20_000)
    |> put_api_key()
  end

  defp apply_preset(changeset) do
    case Presets.get(get_change(changeset, :provider_preset)) do
      nil ->
        changeset

      preset ->
        changeset
        |> put_change(:provider_kind, preset.provider_kind)
        |> put_preset_base_url(preset.base_url)
    end
  end

  defp put_preset_base_url(changeset, default) do
    if get_change(changeset, :base_url),
      do: changeset,
      else: force_change(changeset, :base_url, default)
  end

  defp put_api_key_auth_for_non_anthropic(changeset) do
    if get_field(changeset, :provider_kind) == "anthropic",
      do: changeset,
      else: put_change(changeset, :auth_method, "api_key")
  end

  defp put_api_key(changeset) do
    case {fetch_change(changeset, :api_key), fetch_change(changeset, :auth_method)} do
      {{:ok, key}, _} -> put_change(changeset, :encrypted_api_key, blank_to_nil(key))
      {:error, {:ok, _method}} -> put_change(changeset, :encrypted_api_key, nil)
      {:error, :error} -> changeset
    end
  end

  @doc "What blocks a run: any of `:provider`, `:model`, `:base_url`, `:api_key`."
  def missing(%__MODULE__{} = config) do
    [
      {:provider, is_nil(config.provider_kind)},
      {:model, is_nil(config.model)},
      {:base_url,
       config.provider_kind in ~w(openai_compatible ollama_local) and is_nil(config.base_url)},
      {:api_key, needs_api_key?(config) and is_nil(config.encrypted_api_key)}
    ]
    |> Enum.filter(fn {_field, missing?} -> missing? end)
    |> Enum.map(fn {field, _} -> field end)
  end

  def ready?(%__MODULE__{} = config), do: missing(config) == []

  def subscription?(%__MODULE__{provider_kind: "anthropic", auth_method: "subscription"}),
    do: true

  def subscription?(%__MODULE__{}), do: false

  defp needs_api_key?(%__MODULE__{provider_kind: nil}), do: false
  defp needs_api_key?(%__MODULE__{provider_kind: "ollama_local"}), do: false
  defp needs_api_key?(%__MODULE__{provider_preset: preset}), do: preset not in @keyless_presets

  @doc "The last characters of the stored key, for recognising it without revealing it."
  def api_key_hint(%__MODULE__{encrypted_api_key: key}) when is_binary(key) do
    if String.length(key) > @visible_key_chars * 3,
      do: String.slice(key, -@visible_key_chars, @visible_key_chars),
      else: nil
  end

  def api_key_hint(_), do: nil

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
