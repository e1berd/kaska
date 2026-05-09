defmodule Hardhat.TaskDocs.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Hardhat.TaskDocs.Server

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def lookup_or_start(task_id) when is_binary(task_id) do
    case Registry.lookup(Hardhat.TaskDocs.Registry, task_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(__MODULE__, Server.child_spec(task_id)) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          other -> other
        end
    end
  end
end
