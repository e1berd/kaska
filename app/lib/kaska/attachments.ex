defmodule Kaska.Attachments do
  @moduledoc """
  Attachments live in S3 (RustFS). The flow is:

    1. client requests an upload — we validate constraints, mint a unique
       `storage_key`, write a `pending` row, and return a pre-signed PUT URL.
    2. browser PUTs the file directly to RustFS by that URL.
    3. client confirms — we flip the row to `ready` (and broadcast).

  Stale `pending` rows are an acceptable cost: nothing else points at them
  until they're confirmed, and a janitor task (TODO) can delete them later.
  """

  import Ecto.Query

  alias Kaska.Repo
  alias Kaska.Storage
  alias Kaska.Attachments.Attachment

  # Per-MIME size caps (bytes). Anything not listed defaults to @file_max.
  @image_max 15 * 1024 * 1024
  @video_max 300 * 1024 * 1024
  @file_max 50 * 1024 * 1024

  @parent_types ~w(task user project)

  @doc """
  Creates a `pending` attachment + a pre-signed PUT URL.

  Returns `{:ok, %{attachment: ..., put_url: ...}}` or
  `{:error, %Ecto.Changeset{}}` / `{:error, atom}`.
  """
  def request_upload(parent_type, parent_id, attrs, creator_id)
      when parent_type in @parent_types do
    filename = attrs |> Map.get(:filename) |> to_string()
    mime = attrs |> Map.get(:mime) |> to_string()
    size = Map.get(attrs, :size)

    with :ok <- validate_size(mime, size),
         kind <- classify(mime),
         storage_key <- build_key(parent_type, parent_id, filename) do
      attrs = %{
        parent_type: parent_type,
        parent_id: parent_id,
        kind: kind,
        filename: filename,
        mime: mime,
        size: size,
        storage_key: storage_key,
        status: "pending",
        creator_id: creator_id
      }

      with {:ok, attachment} <-
             %Attachment{} |> Attachment.create_changeset(attrs) |> Repo.insert(),
           {:ok, url} <-
             Storage.presigned_put(storage_key,
               expires_in: 600,
               content_type: mime,
               headers: [{"content-type", mime}]
             ) do
        {:ok, %{attachment: attachment, put_url: url}}
      end
    end
  end

  @doc "Marks a pending attachment as ready. The owner must match `creator_id`."
  def confirm_upload(attachment_id, creator_id) when is_binary(attachment_id) do
    case Repo.get(Attachment, attachment_id) do
      nil ->
        {:error, :not_found}

      %Attachment{creator_id: ^creator_id, status: "pending"} = attachment ->
        attachment |> Attachment.status_changeset("ready") |> Repo.update()

      %Attachment{creator_id: ^creator_id, status: "ready"} = attachment ->
        {:ok, attachment}

      _ ->
        {:error, :forbidden}
    end
  end

  @doc "Removes the attachment record and the underlying S3 object."
  def delete_attachment(%Attachment{} = attachment) do
    _ = Storage.delete_object(attachment.storage_key)
    Repo.delete(attachment)
  end

  def get(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _} -> Repo.get(Attachment, id)
      :error -> nil
    end
  end

  def get(_), do: nil

  def list_for(parent_type, parent_id) when parent_type in @parent_types do
    Repo.all(
      from a in Attachment,
        where:
          a.parent_type == ^parent_type and
            a.parent_id == ^parent_id and
            a.status == "ready",
        order_by: [asc: a.inserted_at]
    )
  end

  @doc """
  Returns ready attachments for many parents at once, grouped by `parent_id`.
  Avoids an N+1 when serialising a list of tasks.
  """
  def list_for_many(parent_type, parent_ids)
      when parent_type in @parent_types and is_list(parent_ids) do
    Repo.all(
      from a in Attachment,
        where:
          a.parent_type == ^parent_type and
            a.parent_id in ^parent_ids and
            a.status == "ready",
        order_by: [asc: a.inserted_at]
    )
    |> Enum.group_by(& &1.parent_id)
  end

  @doc """
  Build a short-lived pre-signed GET URL for an attachment.
  Embeds the public RustFS host so the browser can reach it directly.
  """
  def view_url(%Attachment{storage_key: key}, opts \\ []) do
    expires_in = Keyword.get(opts, :expires_in, 3600)

    case Storage.presigned_get(key, expires_in: expires_in) do
      {:ok, url} -> url
      _ -> nil
    end
  end

  ## ─────────────────────────────────────────────────────────────────

  defp classify(mime) do
    cond do
      String.starts_with?(mime, "image/") -> "image"
      String.starts_with?(mime, "video/") -> "video"
      true -> "file"
    end
  end

  defp validate_size(_, nil), do: {:error, :missing_size}

  defp validate_size(mime, size) when is_integer(size) and size > 0 do
    cap =
      cond do
        String.starts_with?(mime, "image/") -> @image_max
        String.starts_with?(mime, "video/") -> @video_max
        true -> @file_max
      end

    if size > cap, do: {:error, :file_too_large}, else: :ok
  end

  defp validate_size(_, _), do: {:error, :invalid_size}

  defp build_key(parent_type, parent_id, filename) do
    ext =
      filename
      |> Path.extname()
      |> String.downcase()
      |> String.slice(0, 12)
      |> sanitize_ext()

    "#{parent_type}/#{parent_id}/#{Ecto.UUID.generate()}#{ext}"
  end

  defp sanitize_ext(""), do: ""
  defp sanitize_ext("." <> rest), do: "." <> String.replace(rest, ~r/[^a-z0-9]/, "")
end
