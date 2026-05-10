defmodule Mix.Tasks.Users.Promotion do
  use Mix.Task

  alias Kaska.Accounts

  @shortdoc "Promotes a user to a role by email"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts =
      args
      |> normalize_kv_args()
      |> parse_opts()

    email = Keyword.get(opts, :email)
    rank = Keyword.get(opts, :rank)

    with true <- is_binary(email) and email != "",
         true <- rank in ["user", "admin", "superadmin"],
         {:ok, user} <- Accounts.promote_user_by_email(email, rank) do
      Mix.shell().info("User #{user.email} promoted to #{user.role}")
    else
      false ->
        Mix.raise("Usage: mix users.promotion email:<email> rank:<user|admin|superadmin>")

      {:error, :user_not_found} ->
        Mix.raise("User not found")

      {:error, %Ecto.Changeset{} = cs} ->
        Mix.raise("Validation failed: #{inspect(cs.errors)}")

      {:error, reason} ->
        Mix.raise("Promotion failed: #{inspect(reason)}")
    end
  end

  defp parse_opts(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [email: :string, rank: :string])
    opts
  end

  defp normalize_kv_args(args) do
    Enum.map(args, fn
      <<"email:", value::binary>> -> "--email=#{value}"
      <<"rank:", value::binary>> -> "--rank=#{value}"
      value -> value
    end)
  end
end
