defmodule HardhatWeb.UserSocket do
  use Phoenix.Socket

  channel "auth:lobby", HardhatWeb.AuthChannel
  channel "user:*", HardhatWeb.UserChannel
  channel "projects:lobby", HardhatWeb.ProjectsChannel
  channel "board:*", HardhatWeb.BoardChannel
  channel "board_slug:*", HardhatWeb.BoardChannel
  channel "task_doc:*", HardhatWeb.TaskDocChannel
  channel "sys:*", HardhatWeb.SysChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info)
      when is_binary(token) and token != "" do
    case Hardhat.Guardian.resource_from_token(token) do
      {:ok, user, _claims} ->
        {:ok, assign(socket, :current_user, user)}

      _ ->
        {:ok, assign(socket, :current_user, nil)}
    end
  end

  def connect(_params, socket, _connect_info) do
    {:ok, assign(socket, :current_user, nil)}
  end

  @impl true
  def id(%{assigns: %{current_user: %{id: id}}}), do: "user_socket:" <> id
  def id(_), do: nil
end
