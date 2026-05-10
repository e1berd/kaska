defmodule Kaska.S3.ReqClient do
  @moduledoc """
  ExAws HTTP client adapter using `Req`. Implements the `ExAws.Request.HttpClient`
  callbacks so the rest of the codebase can stay on a single HTTP client
  (per AGENTS.md, we avoid hackney/tesla/httpoison).
  """

  @behaviour ExAws.Request.HttpClient

  @impl true
  def request(method, url, body, headers, http_opts) do
    options =
      [
        method: method,
        url: url,
        body: body,
        headers: headers,
        decode_body: false,
        retry: false
      ] ++ Keyword.take(http_opts, [:receive_timeout, :connect_options])

    case Req.request(options) do
      {:ok, %Req.Response{status: status, headers: resp_headers, body: resp_body}} ->
        {:ok, %{status_code: status, headers: normalize_headers(resp_headers), body: resp_body}}

      {:error, exception} ->
        {:error, %{reason: exception}}
    end
  end

  # ex_aws expects `[{"k", "v"}, ...]`; Req hands back `%{"k" => ["v", ...]}` on
  # newer versions. Flatten back into the legacy proplist shape.
  defp normalize_headers(headers) when is_list(headers), do: headers

  defp normalize_headers(headers) when is_map(headers) do
    for {k, vs} <- headers, v <- List.wrap(vs), do: {k, v}
  end
end
