defmodule KaskaWeb.UserChannel do
  use Phoenix.Channel

  alias Kaska.{Accounts, Attachments, Repo}
  alias Kaska.Accounts.User
  alias Kaska.Attachments.Attachment

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

  def handle_in("set_theme", payload, socket) do
    attrs = %{
      theme_slug: normalize_theme_slug(Map.get(payload, "theme_slug")),
      theme_mode: normalize_theme_mode(Map.get(payload, "theme_mode"))
    }

    case socket.assigns.current_user
         |> User.theme_changeset(attrs)
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
            content_type: attrs.mime,
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
        do: Kaska.Storage.delete_object(old_key)

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
      avatar_url: avatar_url(user),
      theme_slug: user.theme_slug,
      theme_mode: user.theme_mode
    }
  end

  defp normalize_theme_slug(nil), do: nil
  defp normalize_theme_slug(""), do: nil
  defp normalize_theme_slug(slug) when is_binary(slug), do: slug
  defp normalize_theme_slug(_), do: nil

  defp normalize_theme_mode(nil), do: nil
  defp normalize_theme_mode(""), do: nil
  defp normalize_theme_mode(mode) when mode in ["light", "dark", "system"], do: mode
  defp normalize_theme_mode(_), do: nil

  defp avatar_url(%User{avatar_key: nil}), do: nil

  defp avatar_url(%User{avatar_key: key}) do
    case Kaska.Storage.presigned_get(key, expires_in: 3600 * 6) do
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
