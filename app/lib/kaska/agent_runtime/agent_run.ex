defmodule Kaska.AgentRuntime.AgentRun do
  @moduledoc """
  One execution of a code-capable agent on one task, i.e. one ephemeral
  container started by `agent-supervisor`. Only the last lines of output live
  in `log_tail`; the full log goes to object storage under `log_object_key`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.{Project, Task}

  @statuses ~w(pending running succeeded failed stopped timed_out)
  @active_statuses ~w(pending running)
  @triggers ~w(manual assigned moved)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "agent_runs" do
    field :trigger, :string, default: "manual"
    field :status, :string, default: "pending"
    field :container_id, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    field :exit_code, :integer
    field :exit_reason, :string
    field :log_tail, :string, default: ""
    field :log_object_key, :string

    belongs_to :agent, User
    belongs_to :task, Task
    belongs_to :project, Project
    belongs_to :requested_by, User
    belongs_to :api_token, Kaska.ApiTokens.ApiToken

    timestamps()
  end

  def statuses, do: @statuses
  def active_statuses, do: @active_statuses
  def terminal_statuses, do: @statuses -- @active_statuses

  def active?(%__MODULE__{status: status}), do: status in @active_statuses

  def create_changeset(run, attrs) do
    run
    |> cast(attrs, [:agent_id, :task_id, :project_id, :requested_by_id, :trigger])
    |> validate_required([:agent_id, :task_id, :project_id])
    |> validate_inclusion(:trigger, @triggers)
    |> unique_constraint(:task_id,
      name: :agent_runs_one_active_per_task,
      message: "already has an active run"
    )
  end

  def start_changeset(run, attrs) do
    run
    |> cast(attrs, [:container_id, :api_token_id])
    |> validate_required([:container_id])
    |> put_change(:status, "running")
    |> put_change(:started_at, now())
  end

  def finish_changeset(run, attrs) do
    run
    |> cast(attrs, [:status, :exit_code, :exit_reason, :log_object_key])
    |> validate_required([:status])
    |> validate_inclusion(:status, terminal_statuses())
    |> put_change(:finished_at, now())
  end

  def log_changeset(run, log_tail) do
    change(run, log_tail: log_tail)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
