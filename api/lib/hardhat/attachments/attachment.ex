defmodule Hardhat.Attachments.Attachment do
  use Ecto.Schema
  import Ecto.Changeset

  alias Hardhat.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  @parent_types ~w(task user project)
  @kinds ~w(image video file)
  @statuses ~w(pending ready)

  schema "attachments" do
    field :parent_type, :string
    field :parent_id, :binary_id
    field :kind, :string
    field :filename, :string
    field :mime, :string
    field :size, :integer
    field :storage_key, :string
    field :status, :string, default: "pending"

    belongs_to :creator, User

    timestamps()
  end

  def create_changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [
      :parent_type,
      :parent_id,
      :kind,
      :filename,
      :mime,
      :size,
      :storage_key,
      :status,
      :creator_id
    ])
    |> validate_required([
      :parent_type,
      :parent_id,
      :kind,
      :filename,
      :mime,
      :size,
      :storage_key
    ])
    |> validate_inclusion(:parent_type, @parent_types)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:size, greater_than: 0)
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_length(:mime, min: 1, max: 128)
    |> unique_constraint(:storage_key)
  end

  def status_changeset(attachment, status) when status in @statuses do
    change(attachment, status: status)
  end
end
