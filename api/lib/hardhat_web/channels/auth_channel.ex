defmodule HardhatWeb.AuthChannel do
  use Phoenix.Channel

  alias Hardhat.{Accounts, Guardian}

  @access_ttl {15, :minutes}
  @refresh_ttl {30, :days}

  @impl true
  def join("auth:lobby", _payload, socket), do: {:ok, socket}

  @impl true
  def handle_in("register", %{"email" => email, "password" => password}, socket) do
    case Accounts.register_user(%{email: email, password: password}) do
      {:ok, user} ->
        Accounts.deliver_verify_email_instructions(user)

        {:reply,
         {:ok,
          %{
            message: "registered. check your inbox to confirm.",
            user: user_view(user)
          }}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  def handle_in("login", %{"email" => email, "password" => password}, socket) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        {:reply, {:error, %{message: "invalid email or password"}}, socket}

      %{confirmed_at: nil} ->
        {:reply, {:error, %{message: "email not verified", code: "email_not_verified"}}, socket}

      user ->
        {:reply, {:ok, issue_tokens(user)}, socket}
    end
  end

  def handle_in("verify_email", %{"token" => token}, socket) do
    case Accounts.confirm_user_by_token(token) do
      {:ok, user} ->
        {:reply, {:ok, %{message: "email verified", user: user_view(user)}}, socket}

      _ ->
        {:reply, {:error, %{message: "invalid or expired token"}}, socket}
    end
  end

  def handle_in("forgot_password", %{"email" => email}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_reset_password_instructions(user)
    end

    # Reply identically whether or not the email exists, to prevent enumeration.
    {:reply, {:ok, %{message: "if account exists, reset email sent"}}, socket}
  end

  def handle_in("reset_password", %{"token" => token, "password" => password}, socket) do
    case Accounts.reset_user_password(token, %{password: password}) do
      {:ok, _user} -> {:reply, {:ok, %{message: "password reset"}}, socket}
      _ -> {:reply, {:error, %{message: "invalid or expired token"}}, socket}
    end
  end

  def handle_in("refresh", %{"refresh" => refresh}, socket) do
    with {:ok, claims} <- Guardian.decode_and_verify(refresh, %{"typ" => "refresh"}),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      Guardian.revoke(refresh)
      {:reply, {:ok, issue_tokens(user)}, socket}
    else
      _ -> {:reply, {:error, %{message: "invalid refresh token"}}, socket}
    end
  end

  defp issue_tokens(user) do
    {:ok, access, _} =
      Guardian.encode_and_sign(user, %{}, token_type: "access", ttl: @access_ttl)

    {:ok, refresh, _} =
      Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: @refresh_ttl)

    %{access: access, refresh: refresh, user: user_view(user)}
  end

  defp user_view(user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      confirmed_at: user.confirmed_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
