defmodule Kaska.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        KaskaWeb.Telemetry,
        Kaska.Repo,
        Kaska.Vault,
        {Task.Supervisor, name: Kaska.AgentRuntime.TaskSupervisor},
        {DNSCluster, query: Application.get_env(:kaska, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Kaska.PubSub},
        KaskaWeb.Presence,
        {Registry, keys: :unique, name: Kaska.TaskDocs.Registry},
        Kaska.TaskDocs.Supervisor,
        KaskaWeb.Endpoint,
        Kaska.Storage.Bootstrap,
        Kaska.Themes.Seeder
      ] ++ agent_runtime_reaper()

    opts = [strategy: :one_for_one, name: Kaska.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp agent_runtime_reaper do
    if Application.get_env(:kaska, :agent_runtime_reaper, true),
      do: [Kaska.AgentRuntime.Reaper],
      else: []
  end

  @impl true
  def config_change(changed, _new, removed) do
    KaskaWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
