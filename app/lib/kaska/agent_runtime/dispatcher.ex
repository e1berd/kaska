defmodule Kaska.AgentRuntime.Dispatcher do
  @moduledoc """
  Drives agent runs through `agent-supervisor`: starts containers for pending
  runs, stops them on request, applies the supervisor's exit reports and reaps
  runs whose container was lost.

  Failure never leaves a run active: if the container cannot be started the
  run is marked `failed` and its PAT is revoked.
  """

  require Logger

  import Ecto.Query

  alias Kaska.{AgentRuntime, Projects, Repo}
  alias Kaska.Accounts.User
  alias Kaska.AgentRuntime.{AgentRun, SupervisorClient}

  @task_supervisor Kaska.AgentRuntime.TaskSupervisor
  @stale_grace_seconds 120
  @pending_timeout_seconds 300

  def dispatch_async(%AgentRun{} = run) do
    {:ok, _pid} = Task.Supervisor.start_child(@task_supervisor, fn -> dispatch(run) end)
    :ok
  end

  def dispatch(%AgentRun{status: "pending", task_id: nil} = run) do
    fail(run, "task was deleted before the run started")
  end

  def dispatch(%AgentRun{status: "pending"} = run) do
    agent = Repo.get!(User, run.agent_id)
    config = AgentRuntime.config_for(agent)
    project = Projects.get_project(run.project_id)

    case AgentRuntime.issue_run_token(run) do
      {:ok, pat, token_id} ->
        env = AgentRuntime.runtime_env(run, config, pat, project.slug)
        start_container(run, env, token_id)

      {:error, _changeset} ->
        fail(run, "could not issue a run token")
    end
  end

  def dispatch(%AgentRun{}), do: {:error, :not_active}

  defp start_container(run, env, token_id) do
    case SupervisorClient.start_run(start_payload(run, env)) do
      {:ok, container_id} ->
        record_started(run, container_id, token_id)

      {:error, reason} ->
        :ok = AgentRuntime.revoke_run_token(run.agent_id, token_id)
        Logger.error("agent run #{run.id} failed to start: #{inspect(reason)}")
        fail(run, "supervisor could not start the container")
    end
  end

  defp record_started(run, container_id, token_id) do
    case AgentRuntime.mark_running(run, container_id, token_id) do
      {:ok, running} ->
        {:ok, running}

      {:error, reason} ->
        :ok = AgentRuntime.revoke_run_token(run.agent_id, token_id)
        stop_container(run.id)
        {:error, reason}
    end
  end

  defp start_payload(run, env) do
    %{
      run_id: run.id,
      image: AgentRuntime.supervisor_setting(:runtime_image),
      env: env,
      limits: %{
        memory_mb: AgentRuntime.supervisor_setting(:memory_mb),
        cpus: AgentRuntime.supervisor_setting(:cpus),
        pids_limit: AgentRuntime.supervisor_setting(:pids_limit),
        walltime_seconds: AgentRuntime.supervisor_setting(:max_walltime_seconds)
      },
      callback_url: AgentRuntime.supervisor_setting(:callback_base_url) <> "/agent_runs/#{run.id}"
    }
  end

  defp fail(run, reason) do
    AgentRuntime.finish_run(run, %{status: "failed", exit_reason: reason})
  end

  @doc "Stops a run on user request. The run is marked `stopped` before the container is killed."
  def stop(%AgentRun{} = run) do
    with {:ok, stopped} <-
           AgentRuntime.finish_run(run, %{status: "stopped", exit_reason: "stopped by user"}) do
      if stopped.container_id, do: stop_container(stopped.id)
      {:ok, stopped}
    end
  end

  defp stop_container(run_id) do
    case SupervisorClient.stop_run(run_id) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("agent run #{run_id} container stop failed: #{inspect(reason)}")
        :error
    end
  end

  @doc """
  Applies an exit report from the supervisor. `outcome` is `exited` (with
  `exit_code`), `timed_out` or `failed`.
  """
  def report_exit(%AgentRun{} = run, %{"outcome" => outcome} = report) do
    exit_code = integer_or_nil(report["exit_code"])

    attrs = %{
      status: status_for(outcome, exit_code),
      exit_code: exit_code,
      exit_reason: report["reason"],
      log_object_key: report["log_object_key"]
    }

    case attrs.status do
      nil -> {:error, :unknown_outcome}
      _ -> AgentRuntime.finish_run(run, attrs)
    end
  end

  def report_exit(%AgentRun{}, _), do: {:error, :unknown_outcome}

  defp status_for("exited", 0), do: "succeeded"
  defp status_for("exited", _), do: "failed"
  defp status_for("timed_out", _), do: "timed_out"
  defp status_for("failed", _), do: "failed"
  defp status_for(_, _), do: nil

  defp integer_or_nil(value) when is_integer(value), do: value
  defp integer_or_nil(_), do: nil

  @doc """
  Finishes runs the supervisor never reported on: `running` past walltime plus
  a grace period become `timed_out`, `pending` never dispatched become `failed`.
  """
  def reap_stale(now \\ DateTime.utc_now()) do
    running_cutoff =
      DateTime.add(
        now,
        -(AgentRuntime.supervisor_setting(:max_walltime_seconds) + @stale_grace_seconds),
        :second
      )

    pending_cutoff = DateTime.add(now, -@pending_timeout_seconds, :second)

    stale =
      Repo.all(
        from r in AgentRun,
          where:
            (r.status == "running" and r.started_at < ^running_cutoff) or
              (r.status == "pending" and r.inserted_at < ^pending_cutoff)
      )

    Enum.count(stale, &reap/1)
  end

  defp reap(%AgentRun{status: "running"} = run) do
    stop_container(run.id)
    finished?(AgentRuntime.finish_run(run, %{status: "timed_out", exit_reason: "no exit report"}))
  end

  defp reap(%AgentRun{} = run) do
    finished?(fail(run, "never dispatched"))
  end

  defp finished?({:ok, _}), do: true
  defp finished?({:error, _}), do: false
end
