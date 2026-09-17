defmodule KaskaWeb.Internal.AgentRunController do
  @moduledoc """
  Reports from `agent-supervisor` about a run's container: streamed output
  (`logs`) and the final exit (`exit`). Reports for runs that are already
  finished answer `409` so the supervisor can stop retrying.
  """

  use KaskaWeb, :controller

  alias Kaska.AgentRuntime
  alias Kaska.AgentRuntime.Dispatcher

  @max_chunk_bytes 64_000

  def logs(conn, %{"id" => id, "chunk" => chunk}) when is_binary(chunk) do
    with_run(conn, id, fn run ->
      run
      |> AgentRuntime.append_log(truncate(chunk))
      |> respond(conn)
    end)
  end

  def logs(conn, _params), do: bad_request(conn)

  def exit(conn, %{"id" => id} = params) do
    with_run(conn, id, fn run ->
      run
      |> Dispatcher.report_exit(params)
      |> respond(conn)
    end)
  end

  defp with_run(conn, id, fun) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case AgentRuntime.get_run(uuid) do
          nil -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
          run -> fun.(run)
        end

      :error ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  defp respond({:ok, run}, conn), do: json(conn, %{id: run.id, status: run.status})

  defp respond({:error, :not_active}, conn),
    do: conn |> put_status(:conflict) |> json(%{error: "not_active"})

  defp respond({:error, :unknown_outcome}, conn), do: bad_request(conn)

  defp respond({:error, %Ecto.Changeset{}}, conn), do: bad_request(conn)

  defp respond({:error, reason}, conn),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})

  defp bad_request(conn), do: conn |> put_status(:bad_request) |> json(%{error: "bad_request"})

  defp truncate(chunk) when byte_size(chunk) <= @max_chunk_bytes, do: chunk

  defp truncate(chunk) do
    chunk
    |> binary_part(byte_size(chunk) - @max_chunk_bytes, @max_chunk_bytes)
    |> String.replace_invalid()
  end
end
