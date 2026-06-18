defmodule Mix.Tasks.Kaska.Import do
  use Mix.Task

  alias Kaska.Repo

  @shortdoc "Imports Kaska data from a zip archive exported by mix kaska.export"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    {opts, argv, _} =
      OptionParser.parse(args,
        strict: [upload: :boolean, "no-files": :boolean],
        aliases: [u: :upload]
      )

    zip_path = List.first(argv)

    unless zip_path && File.exists?(zip_path) do
      Mix.raise("Usage: mix kaska.import <path-to-export.zip> [--upload] [--no-files]")
    end

    upload? = Keyword.get(opts, :upload, false)
    include_files? = not Keyword.get(opts, :"no-files", false)

    tmp_dir = Path.join(System.tmp_dir!(), "kaska-import-#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)

    try do
      Mix.shell().info("Extracting #{zip_path}...")
      extract_zip!(zip_dir(zip_path), tmp_dir)

      manifest = read_json!(Path.join(tmp_dir, "manifest.json"))

      Mix.shell().info(
        "Export version: #{manifest["version"]}, exported at: #{manifest["exported_at"]}"
      )

      Mix.shell().info("Importing data...")
      import_users(tmp_dir)
      import_themes(tmp_dir)
      import_projects(tmp_dir)
      import_columns(tmp_dir)
      import_task_types(tmp_dir)
      import_tasks(tmp_dir)
      import_task_comments(tmp_dir)
      import_project_members(tmp_dir)
      import_project_theme_prefs(tmp_dir)
      import_attachments(tmp_dir)

      if include_files? do
        files_dir = Path.join(tmp_dir, "files")

        if File.dir?(files_dir) do
          upload_s3_files!(files_dir, upload?)
        else
          Mix.shell().info("No files/ directory in archive, skipping S3 upload.")
        end
      end

      Mix.shell().info("Import complete!")
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp import_users(tmp_dir) do
    path = Path.join(tmp_dir, "users.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("users", rows, [:id])
      Mix.shell().info("  users: #{count}")
    end
  end

  defp import_themes(tmp_dir) do
    path = Path.join(tmp_dir, "themes.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("themes", rows, [:id])
      Mix.shell().info("  themes: #{count}")
    end
  end

  defp import_projects(tmp_dir) do
    path = Path.join(tmp_dir, "projects.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("projects", rows, [:id])
      Mix.shell().info("  projects: #{count}")
    end
  end

  defp import_columns(tmp_dir) do
    path = Path.join(tmp_dir, "columns.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("columns", rows, [:id])
      Mix.shell().info("  columns: #{count}")
    end
  end

  defp import_task_types(tmp_dir) do
    path = Path.join(tmp_dir, "task_types.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("task_types", rows, [:id])
      Mix.shell().info("  task_types: #{count}")
    end
  end

  defp import_tasks(tmp_dir) do
    path = Path.join(tmp_dir, "tasks.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("tasks", rows, [:id])
      Mix.shell().info("  tasks: #{count}")
    end
  end

  defp import_task_comments(tmp_dir) do
    path = Path.join(tmp_dir, "task_comments.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("task_comments", rows, [:id])
      Mix.shell().info("  task_comments: #{count}")
    end
  end

  defp import_project_members(tmp_dir) do
    path = Path.join(tmp_dir, "project_members.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("project_members", rows, [:id])
      Mix.shell().info("  project_members: #{count}")
    end
  end

  defp import_project_theme_prefs(tmp_dir) do
    path = Path.join(tmp_dir, "project_theme_prefs.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("project_theme_prefs", rows, [:id])
      Mix.shell().info("  project_theme_prefs: #{count}")
    end
  end

  defp import_attachments(tmp_dir) do
    path = Path.join(tmp_dir, "attachments.json")

    if File.exists?(path) do
      rows = read_json!(path)
      count = upsert_all("attachments", rows, [:id])
      Mix.shell().info("  attachments: #{count}")
    end
  end

  defp upload_s3_files!(files_dir, upload?) do
    files =
      files_dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)

    total = length(files)

    if total > 0 do
      Mix.shell().info("  Uploading #{total} files to S3...")

      if not upload? do
        Mix.shell().info("  (dry run — use --upload to actually upload)")
        :ok
      else
        files
        |> Task.async_stream(
          fn file ->
            storage_key = Path.relative_to(file, files_dir)
            content = File.read!(file)
            bucket = Kaska.Storage.bucket()

            case ExAws.S3.put_object(bucket, storage_key, content) |> ExAws.request() do
              {:ok, _} ->
                :ok

              {:error, reason} ->
                Mix.shell().error("  Failed to upload #{storage_key}: #{inspect(reason)}")
            end
          end,
          timeout: :infinity
        )
        |> Enum.each(fn
          {:ok, :ok} -> :ok
          {:ok, {:error, _}} -> :ok
          {:exit, reason} -> Mix.shell().error("  Upload crashed: #{inspect(reason)}")
        end)
      end
    end
  end

  defp upsert_all(table, rows, conflict_cols) do
    rows = Enum.map(rows, &sanitize_row/1)
    cols = rows |> List.first(%{}) |> Map.keys() |> Enum.map(&String.to_existing_atom/1)

    Repo.insert_all(
      table,
      rows,
      on_conflict: {:replace_all, cols -- conflict_cols},
      conflict_target: conflict_cols
    )
    |> elem(0)
  end

  defp sanitize_row(row) do
    row
    |> Map.new(fn {k, v} ->
      {String.to_existing_atom(k), cast_value(v)}
    end)
  end

  defp cast_value(value) when is_binary(value) do
    cond do
      match?({:ok, _, _}, DateTime.from_iso8601(value)) ->
        {:ok, dt, _} = DateTime.from_iso8601(value)
        dt

      match?({:ok, _}, Date.from_iso8601(value)) ->
        {:ok, date} = Date.from_iso8601(value)
        date

      match?({:ok, _}, NaiveDateTime.from_iso8601(value)) ->
        {:ok, ndt} = NaiveDateTime.from_iso8601(value)
        ndt

      true ->
        value
    end
  end

  defp cast_value(value), do: value

  defp read_json!(path) do
    path |> File.read!() |> Jason.decode!()
  end

  defp zip_dir(path) do
    {:ok, files} = :zip.unzip(String.to_charlist(path), memory: true)
    files
  end

  defp extract_zip!(files, target_dir) do
    Enum.each(files, fn {name, content} ->
      path = Path.join(target_dir, to_string(name))
      path |> Path.dirname() |> File.mkdir_p!()
      File.write!(path, content)
    end)
  end
end
