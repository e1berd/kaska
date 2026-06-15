defmodule KaskaWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates `/api/v1` requests with a personal access token presented as
  `Authorization: Bearer <token>`. On success assigns `:current_user`; otherwise
  replies `401` and halts.
  """

  import Plug.Conn

  alias Kaska.ApiTokens

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, user} <- ApiTokens.verify_token(String.trim(token)) do
      assign(conn, :current_user, user)
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end
