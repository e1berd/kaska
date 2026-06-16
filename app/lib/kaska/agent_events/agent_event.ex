defmodule Kaska.AgentEvents.AgentEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.Project

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "agent_events" do
    field :seq, :integer, read_after_writes: true
    field :type, :string
    field :payload, :map, default: %{}
    belongs_to :agent, User
    belongs_to :project, Project

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:agent_id, :project_id, :type, :payload])
    |> validate_required([:agent_id, :project_id, :type])
    |> foreign_key_constraint(:agent_id)
    |> foreign_key_constraint(:project_id)
  end
end
