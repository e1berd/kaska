defmodule Hardhat.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      HardhatWeb.Telemetry,
      Hardhat.Repo,
      {DNSCluster, query: Application.get_env(:hardhat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Hardhat.PubSub},
      HardhatWeb.Presence,
      HardhatWeb.Endpoint,
      Hardhat.Storage.Bootstrap,
      Hardhat.Themes.Seeder
    ]

    opts = [strategy: :one_for_one, name: Hardhat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    HardhatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
