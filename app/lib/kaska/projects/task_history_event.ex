defmodule Kaska.Projects.TaskHistoryEvent do
  use Ecto.Schema
  import Ecto.Changeset

  alias Kaska.Accounts.User
  alias Kaska.Projects.{Project, Task, TaskHistoryEvent}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime_usec]

  @kinds ~w(created field_changed column_moved)
  @fields ~w(title body_doc task_type_id start_date end_date assignee_ids column_id)

  schema "task_history_events" do
    field :batch_id, :binary_id
    field :kind, :string
    field :field, :string
    field :old_value, :map
    field :new_value, :map
    field :comment, :string
    field :regression, :boolean, default: false

    belongs_to :project, Project
    belongs_to :task, Task
    belongs_to :actor, User
    belongs_to :reverts_event, TaskHistoryEvent

    timestamps(updated_at: false)
  end

  def kinds, do: @kinds
  def fields, do: @fields

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :project_id,
      :task_id,
      :actor_id,
      :batch_id,
      :kind,
      :field,
      :old_value,
      :new_value,
      :comment,
      :regression,
      :reverts_event_id
    ])
    |> validate_required([:project_id, :task_id, :batch_id, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:field, @fields)
    |> validate_length(:comment, max: 4000)
    |> foreign_key_constraint(:project_id)
    |> foreign_key_constraint(:task_id)
    |> foreign_key_constraint(:actor_id)
    |> foreign_key_constraint(:reverts_event_id)
  end
end
