defmodule Hardhat.Projects.TaskDocUpdate do
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "task_doc_updates" do
    field :task_id, :binary_id
    field :seq, :integer
    field :update, :binary
    field :author_id, :binary_id

    field :inserted_at, :utc_datetime
  end
end
