defmodule HardhatWeb.SysChannel do
  use Phoenix.Channel

  alias Hardhat.Accounts

  @impl true
  def join("sys:lobby", _payload, socket) do
    # Anyone can join sys:lobby to get users
    {:ok, %{}, socket}
  end

  @impl true
  def handle_in("get_settings", _payload, socket) do
    if is_admin(socket.assigns[:current_user]) do
      settings = %{
        allow_registration: Accounts.get_setting("allow_registration", "true") == "true"
      }
      {:reply, {:ok, settings}, socket}
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  def handle_in("set_settings", payload, socket) do
    if is_admin(socket.assigns[:current_user]) do
      if Map.has_key?(payload, "allow_registration") do
        Accounts.set_setting("allow_registration", payload["allow_registration"])
      end
      {:reply, {:ok, %{}}, socket}
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  def handle_in("get_users", _payload, socket) do
    # Anyone can see users
    users = Accounts.list_users() |> Enum.map(&user_view/1)
    {:reply, {:ok, users}, socket}
  end

  def handle_in("confirm_user", %{"id" => id}, socket) do
    if is_admin(socket.assigns[:current_user]) do
      case Accounts.get_user(id) do
        nil ->
          {:reply, {:error, %{reason: "user not found"}}, socket}
        user ->
          case Hardhat.Repo.update(Hardhat.Accounts.User.confirm_changeset(user)) do
            {:ok, updated_user} ->
              {:reply, {:ok, user_view(updated_user)}, socket}
            {:error, _} ->
              {:reply, {:error, %{reason: "failed to confirm user"}}, socket}
          end
      end
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  def handle_in("delete_user", %{"id" => id}, socket) do
    if is_admin(socket.assigns[:current_user]) do
      case Accounts.get_user(id) do
        nil ->
          {:reply, {:error, %{reason: "user not found"}}, socket}
        user ->
          case Hardhat.Repo.delete(user) do
            {:ok, _} ->
              {:reply, {:ok, %{id: id}}, socket}
            {:error, _} ->
              {:reply, {:error, %{reason: "failed to delete user"}}, socket}
          end
      end
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  def handle_in("change_user_role", %{"id" => id, "role" => role}, socket) do
    if is_admin(socket.assigns[:current_user]) do
      case Accounts.get_user(id) do
        nil ->
          {:reply, {:error, %{reason: "user not found"}}, socket}
        user ->
          case Hardhat.Repo.update(Hardhat.Accounts.User.changeset_role(user, %{role: role})) do
            {:ok, updated_user} ->
              {:reply, {:ok, user_view(updated_user)}, socket}
            {:error, _} ->
              {:reply, {:error, %{reason: "failed to update role"}}, socket}
          end
      end
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  def handle_in("create_invite", payload, socket) do
    if is_admin(socket.assigns[:current_user]) do
      expires_in_minutes = Map.get(payload, "expires_in_minutes")
      email = Map.get(payload, "email")
      token = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

      expires_at = if expires_in_minutes do
        DateTime.utc_now() |> DateTime.add(expires_in_minutes, :minute)
      else
        nil
      end

      case Accounts.create_invite(%{token: token, email: email, expires_at: expires_at}) do
        {:ok, invite} ->
          if email do
            # Send email here in a real app
            # For now, let's just return the token
            nil
          end
          {:reply, {:ok, %{token: invite.token, expires_at: invite.expires_at, email: invite.email}}, socket}
        {:error, _} ->
          {:reply, {:error, %{reason: "could not create invite"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  defp is_admin(nil), do: false
  defp is_admin(%{role: role}), do: role == :admin
  defp is_admin(_), do: false

  defp user_view(user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      confirmed_at: user.confirmed_at,
      display_name: user.display_name,
      avatar_url: avatar_url(user),
      # TODO: Handle online status/last seen using presence or database timestamps.
      last_seen: user.updated_at
    }
  end

  defp avatar_url(%{avatar_key: nil}), do: nil

  defp avatar_url(%{avatar_key: key}) do
    case Hardhat.Storage.presigned_get(key, expires_in: 3600 * 6) do
      {:ok, url} -> url
      _ -> nil
    end
  end
  defp avatar_url(_), do: nil
end
