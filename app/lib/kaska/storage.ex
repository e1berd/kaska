defmodule Kaska.Storage do
  @moduledoc """
  Thin façade over ex_aws/S3 for working with RustFS.

  Two endpoints exist: the *internal* one (api ↔ rustfs over the docker
  network) is used for direct calls (ensure_bucket, delete_object). The
  *public* endpoint is what we sign into pre-signed URLs because the
  browser hits RustFS from outside the docker network.
  """

  require Logger

  @doc "Returns the S3 bucket name configured for this app."
  def bucket, do: config(:bucket, "kaska")

  @doc """
  Creates the bucket if it does not exist.

  Safe to call on every boot — `:bucket_already_owned_by_you` and similar
  responses are treated as success.
  """
  def ensure_bucket do
    case ExAws.S3.put_bucket(bucket(), "us-east-1") |> ExAws.request() do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 409, _}} ->
        :ok

      {:error, {:http_error, status, _body}} when status in [200, 201, 204] ->
        :ok

      {:error, {:http_error, _, %{body: body}}}
      when is_binary(body) ->
        # RustFS replies with a 200/409 body containing
        # "BucketAlreadyOwnedByYou" / "BucketAlreadyExists" — also fine.
        if body =~ "BucketAlreadyOwnedByYou" or body =~ "BucketAlreadyExists" do
          :ok
        else
          {:error, body}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Pre-signed `PUT` URL the browser uses to upload a single object directly
  to RustFS. The signed host is the *public* endpoint.
  """
  @spec presigned_put(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def presigned_put(key, opts \\ []) do
    presign(:put, key, opts)
  end

  @doc """
  Pre-signed `GET` URL the browser uses to fetch a private object.
  TTL defaults to 1 hour.
  """
  @spec presigned_get(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def presigned_get(key, opts \\ []) do
    presign(:get, key, opts)
  end

  @doc "Deletes an object. No-op if it does not exist."
  def delete_object(key) when is_binary(key) do
    case ExAws.S3.delete_object(bucket(), key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  ## Helpers ──────────────────────────────────────────────────────────

  defp presign(method, key, opts) do
    expires_in = Keyword.get(opts, :expires_in, 3600)
    headers = Keyword.get(opts, :headers, [])

    config = public_aws_config()

    ExAws.S3.presigned_url(config, method, bucket(), key,
      expires_in: expires_in,
      virtual_host: false,
      headers: headers
    )
  end

  # ex_aws builds the URL using whatever scheme/host/port live on the config
  # struct. Override them with the public endpoint so the browser can reach
  # the signed URL.
  defp public_aws_config do
    endpoint = config(:public_endpoint) |> to_string() |> String.trim_trailing("/")

    %{
      ExAws.Config.new(:s3)
      | scheme: URI.parse(endpoint).scheme <> "://",
        host: URI.parse(endpoint).host,
        port: URI.parse(endpoint).port,
        region: "us-east-1"
    }
  end

  defp config(key, default \\ nil) do
    Application.get_env(:kaska, :s3, []) |> Keyword.get(key, default)
  end
end
