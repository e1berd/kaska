defmodule Kaska.AgentRuntime.Presets do
  @moduledoc """
  UI conveniences for picking an LLM provider. A preset only supplies the
  provider kind and a default `base_url`; the runner never branches on it.
  """

  @presets %{
    "anthropic" => %{provider_kind: "anthropic", base_url: nil},
    "openai" => %{provider_kind: "openai_compatible", base_url: "https://api.openai.com/v1"},
    "deepseek" => %{provider_kind: "openai_compatible", base_url: "https://api.deepseek.com/v1"},
    "qwen_dashscope" => %{
      provider_kind: "openai_compatible",
      base_url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    },
    "glm_zhipu" => %{
      provider_kind: "openai_compatible",
      base_url: "https://open.bigmodel.cn/api/paas/v4"
    },
    "xai_grok" => %{provider_kind: "openai_compatible", base_url: "https://api.x.ai/v1"},
    "lm_studio" => %{provider_kind: "openai_compatible", base_url: nil},
    "ollama" => %{provider_kind: "ollama_local", base_url: "http://ollama:11434"},
    "custom" => %{provider_kind: "openai_compatible", base_url: nil}
  }

  def slugs, do: Map.keys(@presets)

  def all, do: @presets

  def get(slug), do: Map.get(@presets, slug)
end
