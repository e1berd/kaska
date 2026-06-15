defmodule Kaska.ApiTokensTest do
  use Kaska.DataCase, async: true

  alias Kaska.ApiTokens
  alias Kaska.Accounts

  defp user_fixture(attrs \\ %{}) do
    email = "user#{System.unique_integer([:positive])}@example.com"

    {:ok, user} =
      attrs
      |> Enum.into(%{email: email, password: "correct horse battery"})
      |> Accounts.register_user()

    user
  end

  describe "create_token/2" do
    test "returns a prefixed plaintext shown once and persists only a hash" do
      user = user_fixture()

      assert {:ok, plaintext, token} = ApiTokens.create_token(user, "ci agent")
      assert String.starts_with?(plaintext, "kaska_pat_")
      assert token.name == "ci agent"
      assert token.user_id == user.id
      assert token.last_four == String.slice(plaintext, -4, 4)
      assert token.token_hash != plaintext
      assert is_binary(token.token_hash)
    end

    test "rejects a blank name" do
      user = user_fixture()
      assert {:error, changeset} = ApiTokens.create_token(user, "")
      assert %{name: _} = errors_on(changeset)
    end
  end

  describe "verify_token/1" do
    test "resolves a live token to its owner and records usage" do
      user = user_fixture()
      {:ok, plaintext, token} = ApiTokens.create_token(user, "agent")

      assert is_nil(token.last_used_at)
      assert {:ok, resolved} = ApiTokens.verify_token(plaintext)
      assert resolved.id == user.id

      assert [touched] = ApiTokens.list_tokens(user)
      refute is_nil(touched.last_used_at)
    end

    test "rejects unknown, malformed, and revoked tokens" do
      user = user_fixture()
      {:ok, plaintext, token} = ApiTokens.create_token(user, "agent")

      assert :error = ApiTokens.verify_token("kaska_pat_nope")
      assert :error = ApiTokens.verify_token(nil)

      assert :ok = ApiTokens.revoke_token(user, token.id)
      assert :error = ApiTokens.verify_token(plaintext)
    end
  end

  describe "revoke_token/2" do
    test "only the owner can revoke, and only once" do
      owner = user_fixture()
      other = user_fixture()
      {:ok, _plaintext, token} = ApiTokens.create_token(owner, "agent")

      assert {:error, :not_found} = ApiTokens.revoke_token(other, token.id)
      assert :ok = ApiTokens.revoke_token(owner, token.id)
      assert {:error, :not_found} = ApiTokens.revoke_token(owner, token.id)
    end
  end
end
