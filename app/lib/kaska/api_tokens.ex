defmodule Kaska.ApiTokens do
  @moduledoc """
  Personal access tokens for the REST API (`/api/v1`). A token authenticates
  as the user that owns it, so the API reuses the same membership checks as the
  channel layer (`Kaska.Projects.member?/2` and friends).

  Only a SHA-256 hash of the token is stored. The plaintext is shown exactly
  once, at creation time. Tokens are long-lived and revocable.
  """

  import Ecto.Query

  alias Kaska.Repo
  alias Kaska.Accounts.User
  alias Kaska.ApiTokens.ApiToken

  @prefix "kaska_pat_"
  @rand_size 32
  @hash_algorithm :sha256

  @doc """
  Creates a token for `user` and returns `{:ok, plaintext, token}`. The
  plaintext (with `#{@prefix}` prefix) is the only time the secret is visible.
  """
  def create_token(%User{id: user_id}, name) do
    plaintext =
      @prefix <> (:crypto.strong_rand_bytes(@rand_size) |> Base.url_encode64(padding: false))

    changeset =
      %ApiToken{
        user_id: user_id,
        token_hash: hash(plaintext),
        last_four: String.slice(plaintext, -4, 4)
      }
      |> ApiToken.create_changeset(%{name: name})

    case Repo.insert(changeset) do
      {:ok, token} -> {:ok, plaintext, token}
      {:error, _} = err -> err
    end
  end

  @doc """
  Resolves a plaintext token to its owner, touching `last_used_at`. Returns
  `{:ok, %User{}}` for a live (non-revoked) token, otherwise `:error`.
  """
  def verify_token(plaintext) when is_binary(plaintext) do
    hashed = hash(plaintext)

    query =
      from t in ApiToken,
        where: t.token_hash == ^hashed and is_nil(t.revoked_at),
        join: u in assoc(t, :user),
        select: {t, u}

    case Repo.one(query) do
      {token, user} ->
        touch_last_used(token)
        {:ok, user}

      nil ->
        :error
    end
  end

  def verify_token(_), do: :error

  def list_tokens(%User{id: user_id}) do
    Repo.all(
      from t in ApiToken,
        where: t.user_id == ^user_id,
        order_by: [desc: t.inserted_at]
    )
  end

  def revoke_all_for_user(user_id) when is_binary(user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.update_all(
        from(t in ApiToken, where: t.user_id == ^user_id and is_nil(t.revoked_at)),
        set: [revoked_at: now, updated_at: now]
      )

    {:ok, count}
  end

  def revoke_token(%User{id: user_id}, token_id) when is_binary(token_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.update_all(
        from(t in ApiToken,
          where: t.id == ^token_id and t.user_id == ^user_id and is_nil(t.revoked_at)
        ),
        set: [revoked_at: now, updated_at: now]
      )

    if count == 1, do: :ok, else: {:error, :not_found}
  end

  defp touch_last_used(%ApiToken{id: id}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    Repo.update_all(from(t in ApiToken, where: t.id == ^id), set: [last_used_at: now])
  end

  defp hash(plaintext), do: :crypto.hash(@hash_algorithm, plaintext)
end
