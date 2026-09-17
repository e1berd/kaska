defmodule Kaska.AgentRuntime do
  @moduledoc """
  Control plane for agents that run inside `agent-supervisor` containers.
  Holds each agent's runtime config and the history of its runs; never touches
  Docker itself.

  Run lifecycle: `request_run/4` inserts a `pending` run (at most one active run
  per task, bounded per owner), `mark_running/3` records the container and the
  per-run token, `finish_run/2` moves it to a terminal status and revokes the
  token. Every transition is broadcast as `{:agent_run_updated, run}` on
  `run_topic/1`, `task_runs_topic/1`, `project_runs_topic/1` and
  `owner_runs_topic/1` of the agent's owner; runner output
  as `{:agent_run_log, run_id, chunk}` on `run_topic/1`.
  """

  import Ecto.Query

  alias Kaska.{ApiTokens, Projects, Repo}
  alias Kaska.Accounts.User
  alias Kaska.AgentRuntime.{AgentConfig, AgentRun}
  alias Kaska.Projects.Task

  @log_tail_max_lines 200

  def run_topic(run_id), do: "agent_runtime:run:#{run_id}"
  def task_runs_topic(task_id), do: "agent_runtime:task:#{task_id}"
  def project_runs_topic(project_id), do: "agent_runtime:project:#{project_id}"
  def owner_runs_topic(owner_id), do: "agent_runtime:owner:#{owner_id}"

  def get_config(agent_id) when is_binary(agent_id), do: Repo.get(AgentConfig, agent_id)

  def config_for(%User{is_agent: true, id: agent_id}) do
    get_config(agent_id) || %AgentConfig{agent_id: agent_id}
  end

  def upsert_config(%User{is_agent: true} = agent, attrs) do
    agent
    |> config_for()
    |> AgentConfig.changeset(attrs)
    |> Repo.insert_or_update()
  end

  def ready?(%User{is_agent: true} = agent), do: agent |> config_for() |> AgentConfig.ready?()

  def api_key_set?(%AgentConfig{encrypted_api_key: key}), do: is_binary(key)

  @doc """
  Requests a run of `agent` on `task`. The agent must be fully configured and
  assigned to the task, the task must have no active run, and the agent's owner
  must be under `max_active_runs_per_owner`.
  """
  def request_run(
        %User{is_agent: true} = agent,
        %Task{} = task,
        requested_by_id,
        trigger \\ "manual"
      ) do
    with :ok <- ensure_configured(agent),
         :ok <- ensure_assigned(agent, task),
         :ok <- ensure_member(agent, task),
         :ok <- ensure_owner_quota(agent) do
      %AgentRun{}
      |> AgentRun.create_changeset(%{
        agent_id: agent.id,
        task_id: task.id,
        project_id: task.project_id,
        requested_by_id: requested_by_id,
        trigger: trigger
      })
      |> Repo.insert()
      |> case do
        {:ok, run} -> broadcast_updated({:ok, run})
        {:error, %Ecto.Changeset{errors: [task_id: _]}} -> {:error, :already_running}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  defp ensure_configured(agent) do
    if ready?(agent), do: :ok, else: {:error, :not_configured}
  end

  defp ensure_assigned(%User{id: agent_id}, %Task{id: task_id}) do
    if Projects.assigned?(task_id, agent_id), do: :ok, else: {:error, :not_assigned}
  end

  defp ensure_member(agent, task) do
    if Projects.member?(task.project_id, agent.id), do: :ok, else: {:error, :not_member}
  end

  defp ensure_owner_quota(%User{agent_owner_id: owner_id}) do
    if count_active_runs_for_owner(owner_id) < max_active_runs_per_owner(),
      do: :ok,
      else: {:error, :quota_exceeded}
  end

  def count_active_runs_for_owner(owner_id) do
    Repo.aggregate(
      from(r in AgentRun,
        join: a in User,
        on: a.id == r.agent_id,
        where: a.agent_owner_id == ^owner_id and r.status in ^AgentRun.active_statuses()
      ),
      :count
    )
  end

  def get_run(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(AgentRun, uuid)
      :error -> nil
    end
  end

  def get_run(_), do: nil

  def active_run_for_token(token_id) when is_binary(token_id) do
    Repo.one(
      from r in AgentRun,
        where: r.api_token_id == ^token_id and r.status in ^AgentRun.active_statuses()
    )
  end

  def active_runs_for_agent(agent_id) when is_binary(agent_id) do
    Repo.all(
      from r in AgentRun,
        where: r.agent_id == ^agent_id and r.status in ^AgentRun.active_statuses()
    )
  end

  @doc "The newest run of each task in the project that has any, keyed by task id."
  def latest_runs_by_task(project_id) when is_binary(project_id) do
    from(r in AgentRun,
      where: r.project_id == ^project_id and not is_nil(r.task_id),
      distinct: r.task_id,
      order_by: [asc: r.task_id, desc: r.inserted_at]
    )
    |> Repo.all()
    |> Map.new(&{&1.task_id, &1})
  end

  def active_run_for_task(task_id) when is_binary(task_id) do
    Repo.one(
      from r in AgentRun,
        where: r.task_id == ^task_id and r.status in ^AgentRun.active_statuses()
    )
  end

  def list_runs_for_task(task_id, limit \\ 20) when is_binary(task_id) do
    Repo.all(
      from r in AgentRun,
        where: r.task_id == ^task_id,
        order_by: [desc: r.inserted_at],
        limit: ^limit
    )
  end

  def list_runs_for_agent(agent_id, limit \\ 50) when is_binary(agent_id) do
    Repo.all(
      from r in AgentRun,
        where: r.agent_id == ^agent_id,
        order_by: [desc: r.inserted_at],
        limit: ^limit
    )
  end

  @doc """
  Issues the PAT the runner container authenticates with. It is scoped to this
  run by name and revoked in `finish_run/2`.
  """
  def issue_run_token(%AgentRun{} = run) do
    agent = Repo.get!(User, run.agent_id)

    case ApiTokens.create_token(agent, "run:#{run.id}") do
      {:ok, plaintext, token} -> {:ok, plaintext, token.id}
      {:error, _} = error -> error
    end
  end

  def mark_running(%AgentRun{id: id}, container_id, api_token_id) do
    id
    |> transition(["pending"], fn run ->
      AgentRun.start_changeset(run, %{container_id: container_id, api_token_id: api_token_id})
    end)
    |> broadcast_updated()
  end

  @doc """
  Moves an active run to a terminal status. Finishing an already finished run
  is a no-op returning `{:error, :not_active}`, so repeated supervisor callbacks
  are safe.
  """
  def finish_run(%AgentRun{id: id}, attrs) do
    with {:ok, run} <-
           transition(id, AgentRun.active_statuses(), &AgentRun.finish_changeset(&1, attrs)) do
      :ok = revoke_run_token(run.agent_id, run.api_token_id)
      broadcast_updated({:ok, run})
    end
  end

  def revoke_run_token(_agent_id, nil), do: :ok

  def revoke_run_token(agent_id, token_id) do
    case ApiTokens.revoke_token(%User{id: agent_id}, token_id) do
      :ok -> :ok
      {:error, :not_found} -> :ok
    end
  end

  @doc """
  Appends runner output to the stored tail and pushes the raw chunk on
  `run_topic/1` as `{:agent_run_log, run_id, chunk}` for live consoles.
  """
  def append_log(%AgentRun{id: id}, chunk) when is_binary(chunk) do
    with {:ok, run} <-
           transition(id, AgentRun.active_statuses(), fn run ->
             AgentRun.log_changeset(run, trim_log_tail(run.log_tail <> chunk))
           end) do
      Phoenix.PubSub.broadcast(Kaska.PubSub, run_topic(id), {:agent_run_log, id, chunk})
      {:ok, run}
    end
  end

  defp trim_log_tail(log) do
    log
    |> String.split("\n")
    |> Enum.take(-(@log_tail_max_lines + 1))
    |> Enum.join("\n")
  end

  defp transition(run_id, allowed_statuses, build_changeset) do
    Repo.transaction(fn ->
      locked =
        Repo.one(from r in AgentRun, where: r.id == ^run_id, lock: "FOR UPDATE")

      cond do
        is_nil(locked) -> Repo.rollback(:not_found)
        locked.status not in allowed_statuses -> Repo.rollback(:not_active)
        true -> locked |> build_changeset.() |> Repo.update() |> unwrap_or_rollback()
      end
    end)
  end

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)

  @doc """
  Environment for the runner container. Decrypts the LLM key; the result must
  only ever be handed to the supervisor, never logged or rendered.
  """
  def runtime_env(%AgentRun{} = run, %AgentConfig{} = config, pat, project_slug) do
    %{
      "KASKA_API_URL" => supervisor_setting(:kaska_api_url),
      "KASKA_PAT" => pat,
      "KASKA_RUN_ID" => run.id,
      "TASK_ID" => run.task_id,
      "PROJECT_SLUG" => project_slug,
      "LLM_PROVIDER_KIND" => config.provider_kind,
      "LLM_BASE_URL" => config.base_url || "",
      "LLM_MODEL" => config.model,
      "LLM_API_KEY" => config.encrypted_api_key || "",
      "SYSTEM_PROMPT" => config.system_prompt || "",
      "MAX_TURNS" => Integer.to_string(supervisor_setting(:max_turns))
    }
  end

  def max_active_runs_per_owner, do: supervisor_setting(:max_active_runs_per_owner)

  def supervisor_setting(key) do
    :kaska |> Application.get_env(:agent_supervisor, []) |> Keyword.fetch!(key)
  end

  defp broadcast_updated({:ok, %AgentRun{} = run}) do
    message = {:agent_run_updated, run}
    Phoenix.PubSub.broadcast(Kaska.PubSub, run_topic(run.id), message)

    Phoenix.PubSub.broadcast(Kaska.PubSub, project_runs_topic(run.project_id), message)

    if owner_id = agent_owner_id(run.agent_id) do
      Phoenix.PubSub.broadcast(Kaska.PubSub, owner_runs_topic(owner_id), message)
    end

    if run.task_id do
      Phoenix.PubSub.broadcast(Kaska.PubSub, task_runs_topic(run.task_id), message)
    end

    {:ok, run}
  end

  defp broadcast_updated(error), do: error

  defp agent_owner_id(agent_id) do
    Repo.one(from u in User, where: u.id == ^agent_id, select: u.agent_owner_id)
  end
end
