defmodule HardhatWeb.HealthController do
  use HardhatWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
