defmodule Hardhat.Projects.TaskDocSnapshot do
  use Ecto.Schema

  @primary_key false
  @foreign_key_type :binary_id

  schema "task_doc_snapshots" do
    field :task_id, :binary_id, primary_key: true
    field :snapshot, :binary
    field :state_vector, :binary
    field :seq, :integer

    field :updated_at, :utc_datetime
  end
end
