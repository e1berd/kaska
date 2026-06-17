defmodule Kaska.AgentEvents.AgentEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.{Project, Task, TaskComment}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "agent_events" do
    field :event_type, :string
    field :payload, :map, default: %{}
    field :acked_at, :utc_datetime

    belongs_to :project, Project
    belongs_to :task, Task
    belongs_to :comment, TaskComment
    belongs_to :agent, User

    timestamps()
  end

  def create_changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type, :payload, :project_id, :task_id, :comment_id, :agent_id])
    |> validate_required([:event_type, :project_id, :agent_id])
  end

  def ack_changeset(event) do
    event
    |> change(%{acked_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end
end
