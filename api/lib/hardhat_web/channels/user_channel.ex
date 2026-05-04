defmodule HardhatWeb.UserChannel do
  use Phoenix.Channel

  @impl true
  def join("user:" <> id, _payload, %{assigns: %{current_user: %{id: user_id}}} = socket)
      when id == user_id do
    {:ok, %{user: user_view(socket.assigns.current_user)}, socket}
  end

  def join("user:" <> _id, _payload, %{assigns: %{current_user: nil}}) do
    {:error, %{reason: "unauthenticated"}}
  end

  def join("user:" <> _id, _payload, _socket) do
    {:error, %{reason: "forbidden"}}
  end

  @impl true
  def handle_in("me", _payload, socket) do
    {:reply, {:ok, user_view(socket.assigns.current_user)}, socket}
  end

  defp user_view(user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      confirmed_at: user.confirmed_at
    }
  end
end
