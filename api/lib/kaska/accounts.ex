defmodule Kaska.Accounts do
  @moduledoc """
  IAM context: registration, login, email verification, password reset.
  All flows are surfaced via Phoenix Channels (no REST).
  """

  alias Kaska.Repo
  alias Kaska.Accounts.{User, UserToken, UserNotifier, Setting, Invite}

  def get_setting(key, default \\ nil) do
    case Repo.get_by(Setting, key: to_string(key)) do
      nil -> default
      setting -> setting.value
    end
  end

  def set_setting(key, value) do
    key_str = to_string(key)
    val_str = to_string(value)

    case Repo.get_by(Setting, key: key_str) do
      nil ->
        %Setting{}
        |> Setting.changeset(%{key: key_str, value: val_str})
        |> Repo.insert()

      setting ->
        setting
        |> Setting.changeset(%{value: val_str})
        |> Repo.update()
    end
  end

  def get_invite(token) do
    Repo.get_by(Invite, token: token)
  end

  def create_invite(attrs) do
    %Invite{}
    |> Invite.changeset(attrs)
    |> Repo.insert()
  end

  def delete_invite(%Invite{} = invite) do
    Repo.delete(invite)
  end

  def get_user(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get(User, id)
      :error -> nil
    end
  end

  def get_user(_), do: nil

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email |> String.downcase() |> String.trim())
  end

  def get_user_by_email(_), do: nil

  def list_users do
    Repo.all(User)
  end

  def users_count do
    Repo.aggregate(User, :count, :id)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def register_user_with_bootstrap(attrs) do
    Repo.transaction(fn ->
      Repo.query!("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE")
      first_user = users_count() == 0

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset =
        %User{}
        |> User.registration_changeset(attrs)
        |> maybe_apply_bootstrap(first_user, now)

      case Repo.insert(changeset) do
        {:ok, user} -> {:ok, user, first_user}
        {:error, changeset} -> Repo.rollback({:error, changeset})
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, {:error, changeset}} -> {:error, changeset}
      {:error, reason} -> {:error, reason}
    end
  end

  def promote_user_by_email(email, role) when is_binary(email) do
    with %User{} = user <- get_user_by_email(email),
         {:ok, updated} <- user |> User.changeset_role(%{role: role}) |> Repo.update() do
      {:ok, updated}
    else
      nil -> {:error, :user_not_found}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
      {:error, reason} -> {:error, reason}
    end
  end

  def deliver_verify_email_instructions(%User{confirmed_at: nil} = user) do
    {token, struct} = UserToken.build_email_token(user, "verify_email")
    Repo.insert!(struct)
    UserNotifier.deliver_verify_email_instructions(user, build_url("/verify/", token))
  end

  def deliver_verify_email_instructions(_user), do: {:error, :already_confirmed}

  def confirm_user_by_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "verify_email"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  def deliver_reset_password_instructions(%User{} = user) do
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
    {token, struct} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(struct)
    UserNotifier.deliver_reset_password_instructions(user, build_url("/reset/", token))
  end

  def reset_user_password(token, attrs) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(reset_password_multi(user, attrs)) do
      {:ok, user}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["verify_email"])
    )
  end

  defp reset_password_multi(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["reset_password"])
    )
  end

  defp build_url(path, token) do
    base = System.get_env("WEB_BASE_URL", "http://localhost:5173")
    base <> path <> token
  end

  defp maybe_apply_bootstrap(changeset, false, _now), do: changeset

  defp maybe_apply_bootstrap(changeset, true, now) do
    changeset
    |> Ecto.Changeset.put_change(:role, :superadmin)
    |> Ecto.Changeset.put_change(:confirmed_at, now)
  end
end
