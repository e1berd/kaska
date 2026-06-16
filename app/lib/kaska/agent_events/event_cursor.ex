defmodule Kaska.AgentEvents.EventCursor do
  use Ecto.Schema

  alias Kaska.Accounts.User

  @primary_key false
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "agent_event_cursors" do
    belongs_to :agent, User, primary_key: true
    field :acked_seq, :integer, default: 0

    timestamps()
  end
end
