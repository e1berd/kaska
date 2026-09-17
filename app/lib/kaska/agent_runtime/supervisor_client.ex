defmodule Kaska.AgentRuntime.SupervisorClient do
  @moduledoc """
  HTTP client for the internal `agent-supervisor` API. Authenticates with the
  shared secret as a bearer token. Request payloads carry decrypted secrets in
  `env`, so neither requests nor their bodies are ever logged here.
  """

  alias Kaska.AgentRuntime

  @doc """
  Asks the supervisor to create and start the runner container. Returns
  `{:ok, container_id}`.
  """
  def start_run(%{run_id: _, image: _, env: _, limits: _, callback_url: _} = payload) do
    case Req.post(request(), url: "/runs", json: payload) do
      {:ok, %Req.Response{status: status, body: %{"container_id" => container_id}}}
      when status in 200..299 and is_binary(container_id) ->
        {:ok, container_id}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:supervisor_status, status}}

      {:error, exception} ->
        {:error, {:supervisor_unreachable, Exception.message(exception)}}
    end
  end

  @doc "Asks the supervisor to kill and remove the run's container. Unknown runs are fine."
  def stop_run(run_id) when is_binary(run_id) do
    case Req.post(request(), url: "/runs/#{run_id}/stop") do
      {:ok, %Req.Response{status: status}} when status in 200..299 or status == 404 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:supervisor_status, status}}
      {:error, exception} -> {:error, {:supervisor_unreachable, Exception.message(exception)}}
    end
  end

  defp request do
    Req.new(
      base_url: AgentRuntime.supervisor_setting(:url),
      auth: {:bearer, AgentRuntime.supervisor_setting(:shared_secret) || ""},
      retry: false,
      receive_timeout: 30_000
    )
    |> Req.merge(Application.get_env(:kaska, :agent_supervisor_req_options, []))
  end
end
