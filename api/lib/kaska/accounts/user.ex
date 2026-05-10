defmodule Kaska.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "users" do
    field :email, :string
    field :hashed_password, :string, redact: true
    field :password, :string, virtual: true, redact: true
    field :confirmed_at, :utc_datetime
    field :role, Ecto.Enum, values: [:user, :admin, :superadmin], default: :user
    field :display_name, :string
    field :avatar_key, :string
    field :theme_slug, :string
    field :theme_mode, Ecto.Enum, values: [:light, :dark, :system]

    timestamps()
  end

  def theme_changeset(user, attrs) do
    user
    |> cast(attrs, [:theme_slug, :theme_mode])
    |> validate_length(:theme_slug, min: 2, max: 64)
  end

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name])
    |> validate_length(:display_name, min: 1, max: 60)
  end

  def avatar_changeset(user, attrs) do
    user
    |> cast(attrs, [:avatar_key])
    |> validate_length(:avatar_key, max: 512)
  end

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_email()
    |> validate_password()
    |> put_hashed_password()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> put_hashed_password()
  end

  def confirm_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  def changeset_role(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_inclusion(:role, [:user, :admin, :superadmin])
  end

  def valid_password?(%__MODULE__{hashed_password: hashed}, password)
      when is_binary(hashed) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hashed)
  end

  def valid_password?(_, _), do: Bcrypt.no_user_verify()

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &(&1 |> to_string() |> String.downcase() |> String.trim()))
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "невалидная почта")
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Kaska.Repo)
    |> unique_constraint(:email)
  end

  defp validate_password(changeset) do
    changeset
    |> validate_length(:password, min: 8, max: 72)
  end

  defp put_hashed_password(%{valid?: true, changes: %{password: pw}} = changeset) do
    changeset
    |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(pw))
    |> delete_change(:password)
  end

  defp put_hashed_password(changeset), do: changeset
end
