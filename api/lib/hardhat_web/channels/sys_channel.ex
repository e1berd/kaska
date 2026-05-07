defmodule HardhatWeb.SysChannel do
  use Phoenix.Channel

  alias Hardhat.Accounts

  @impl true
  def join("sys:lobby", _payload, %{assigns: %{current_user: %{id: _id}}} = socket) do
    {:ok, %{}, socket}
  end

  def join("sys:lobby", _payload, _socket) do
    {:error, %{reason: "unauthenticated"}}
  end

  @impl true
  def handle_in("get_settings", _payload, socket) do
    if is_admin(socket.assigns.current_user) do
      settings = %{
        allow_registration: Accounts.get_setting("allow_registration", "true") == "true"
      }
      {:reply, {:ok, settings}, socket}
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  def handle_in("set_settings", payload, socket) do
    if is_admin(socket.assigns.current_user) do
      if Map.has_key?(payload, "allow_registration") do
        Accounts.set_setting("allow_registration", payload["allow_registration"])
      end
      {:reply, {:ok, %{}}, socket}
    else
      {:reply, {:error, %{reason: "forbidden"}}, socket}
    end
  end

  def handle_in("get_users", _payload, socket) do
    # Anyone authenticated can see users (you might want to restrict this)
    users = Accounts.list_users() |> Enum.map(&user_view/1)
    {:reply, {:ok, users}, socket}
  end

  def handle_in("create_invite", payload, socket) do
    if is_admin(socket.assigns.current_user) do
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
