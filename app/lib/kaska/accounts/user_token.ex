defmodule Kaska.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query

  alias Kaska.Accounts.{User, UserToken}

  @hash_algorithm :sha256
  @rand_size 32

  @verify_email_validity_in_days 7
  @reset_password_validity_in_days 1

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    belongs_to :user, User

    timestamps(updated_at: false)
  end

  @doc """
  Returns `{plaintext_token, %UserToken{}}` where plaintext is what we email
  to the user, and the struct (with hashed token) is what we persist.
  """
  def build_email_token(user, context) when context in ["verify_email", "reset_password"] do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed,
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  def verify_email_token_query(token, context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        days = days_for_context(context)

        query =
          from t in UserToken,
            join: u in assoc(t, :user),
            where:
              t.token == ^hashed and t.context == ^context and
                t.inserted_at > ago(^days, "day"),
            select: u

        {:ok, query}

      :error ->
        :error
    end
  end

  def by_user_and_contexts_query(%User{id: user_id}, contexts) do
    from t in UserToken, where: t.user_id == ^user_id and t.context in ^contexts
  end

  defp days_for_context("verify_email"), do: @verify_email_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
end
