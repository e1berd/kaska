defmodule KaskaWeb.AgentViews do
  @moduledoc """
  Channel payloads for agents and their runs, shared by the agents, board and
  run channels. Never includes the API key, container id or run token.
  """

  alias Kaska.AgentRuntime
  alias Kaska.AgentRuntime.{AgentConfig, AgentRun, Presets}
  alias Kaska.Accounts.User

  def run(%AgentRun{} = r) do
    %{
      id: r.id,
      agent_id: r.agent_id,
      task_id: r.task_id,
      project_id: r.project_id,
      requested_by_id: r.requested_by_id,
      trigger: r.trigger,
      status: r.status,
      started_at: r.started_at,
      finished_at: r.finished_at,
      exit_code: r.exit_code,
      exit_reason: r.exit_reason,
      inserted_at: r.inserted_at
    }
  end

  def config(%User{is_agent: true} = agent), do: agent |> AgentRuntime.config_for() |> config()

  def config(%AgentConfig{} = c) do
    %{
      provider_kind: c.provider_kind,
      provider_preset: c.provider_preset,
      base_url: c.base_url,
      model: c.model,
      api_key_set: AgentRuntime.api_key_set?(c),
      api_key_hint: AgentConfig.api_key_hint(c),
      system_prompt: c.system_prompt,
      ready: AgentConfig.ready?(c),
      missing: AgentConfig.missing(c)
    }
  end

  def board_agent(%User{is_agent: true} = agent) do
    c = AgentRuntime.config_for(agent)
    %{provider_preset: c.provider_preset, model: c.model, ready: AgentConfig.ready?(c)}
  end

  def board_agent(_), do: nil

  def presets do
    Presets.all()
    |> Enum.map(fn {slug, preset} ->
      %{slug: slug, provider_kind: preset.provider_kind, base_url: preset.base_url}
    end)
    |> Enum.sort_by(& &1.slug)
  end

  def limits do
    %{
      max_active_runs_per_owner: AgentRuntime.max_active_runs_per_owner(),
      max_walltime_seconds: AgentRuntime.supervisor_setting(:max_walltime_seconds),
      max_turns: AgentRuntime.supervisor_setting(:max_turns)
    }
  end
end
