defmodule KaskaWeb.Plugs.InternalAuth do
  @moduledoc """
  Guards `/internal` routes called by `agent-supervisor`: requires
  `Authorization: Bearer <AGENT_SUPERVISOR_SECRET>`. With no secret configured
  every request is rejected. Caddy never proxies `/internal` publicly.
  """

  import Plug.Conn

  alias Kaska.AgentRuntime

  def init(opts), do: opts

  def call(conn, _opts) do
    expected = AgentRuntime.supervisor_setting(:shared_secret)

    with secret when is_binary(secret) and secret != "" <- expected,
         ["Bearer " <> presented] <- get_req_header(conn, "authorization"),
         true <- Plug.Crypto.secure_compare(String.trim(presented), secret) do
      conn
    else
      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, Jason.encode!(%{error: "unauthorized"}))
        |> halt()
    end
  end
end
