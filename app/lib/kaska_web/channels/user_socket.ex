defmodule KaskaWeb.UserSocket do
  use Phoenix.Socket

  channel "auth:lobby", KaskaWeb.AuthChannel
  channel "user:*", KaskaWeb.UserChannel
  channel "projects:user:*", KaskaWeb.ProjectsChannel
  channel "scouts:user:*", KaskaWeb.ScoutsChannel
  channel "board:*", KaskaWeb.BoardChannel
  channel "board_slug:*", KaskaWeb.BoardChannel
  channel "task_doc:*", KaskaWeb.TaskDocChannel
  channel "sys:*", KaskaWeb.SysChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info)
      when is_binary(token) and token != "" do
    user =
      case Kaska.Guardian.resource_from_token(token) do
        {:ok, user, _claims} ->
          user

        _ ->
          case Kaska.ApiTokens.verify_token(token) do
            {:ok, user} -> user
            :error -> nil
          end
      end

    {:ok, assign(socket, :current_user, user)}
  end

  def connect(_params, socket, _connect_info) do
    {:ok, assign(socket, :current_user, nil)}
  end

  @impl true
  def id(%{assigns: %{current_user: %{id: id}}}), do: "user_socket:" <> id
  def id(_), do: nil
end
