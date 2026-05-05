defmodule HardhatWeb.UserChannel do
  use Phoenix.Channel

  alias Hardhat.{Accounts, Attachments, Repo}
  alias Hardhat.Accounts.User
  alias Hardhat.Attachments.Attachment

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
    user = Accounts.get_user(socket.assigns.current_user.id) || socket.assigns.current_user
    socket = assign(socket, :current_user, user)
    {:reply, {:ok, user_view(user)}, socket}
  end

  def handle_in("update_profile", payload, socket) do
    attrs = %{display_name: Map.get(payload, "display_name")}

    case socket.assigns.current_user
         |> User.profile_changeset(attrs)
         |> Repo.update() do
      {:ok, user} ->
        {:reply, {:ok, user_view(user)}, assign(socket, :current_user, user)}

      {:error, cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}
    end
  end

  def handle_in("request_avatar_upload", payload, socket) do
    user = socket.assigns.current_user

    attrs = %{
      filename: Map.get(payload, "filename"),
      mime: Map.get(payload, "mime"),
      size: Map.get(payload, "size")
    }

    case Attachments.request_upload("user", user.id, attrs, user.id) do
      {:ok, %{attachment: attachment, put_url: url}} ->
        {:reply,
         {:ok,
          %{
            attachment_id: attachment.id,
            put_url: url,
            storage_key: attachment.storage_key
          }}, socket}

      {:error, %Ecto.Changeset{} = cs} ->
        {:reply, {:error, %{errors: format_errors(cs)}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  def handle_in("confirm_avatar_upload", %{"attachment_id" => id}, socket) do
    user = socket.assigns.current_user

    with {:ok, %Attachment{} = attachment} <- Attachments.confirm_upload(id, user.id),
         true <- attachment.parent_type == "user" and attachment.parent_id == user.id,
         old_key = user.avatar_key,
         {:ok, user} <-
           user
           |> User.avatar_changeset(%{avatar_key: attachment.storage_key})
           |> Repo.update() do
      # Old avatar object is no longer referenced — best-effort cleanup.
      if old_key && old_key != attachment.storage_key,
        do: Hardhat.Storage.delete_object(old_key)

      {:reply, {:ok, user_view(user)}, assign(socket, :current_user, user)}
    else
      false -> {:reply, {:error, %{message: "forbidden"}}, socket}
      {:error, reason} -> {:reply, {:error, %{message: to_string(reason)}}, socket}
    end
  end

  defp user_view(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      confirmed_at: user.confirmed_at,
      display_name: user.display_name,
      avatar_url: avatar_url(user)
    }
  end

  defp avatar_url(%User{avatar_key: nil}), do: nil

  defp avatar_url(%User{avatar_key: key}) do
    case Hardhat.Storage.presigned_get(key, expires_in: 3600 * 6) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
