defmodule Mix.Tasks.Kaska.Export do
  use Mix.Task

  import Ecto.Query

  alias Kaska.Repo

  @shortdoc "Exports all Kaska data to a zip archive"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts =
      args
      |> normalize_kv_args()
      |> parse_opts()

    output_path = Keyword.get(opts, :output, default_output_path())
    include_files? = not Keyword.get(opts, :"no-files", false)

    Mix.shell().info("Exporting Kaska data...")
    Mix.shell().info("Output: #{output_path}")
    Mix.shell().info("Include S3 files: #{include_files?}")

    tmp_dir = Path.join(System.tmp_dir!(), "kaska-export-#{Ecto.UUID.generate()}")
    File.mkdir_p!(tmp_dir)

    try do
      manifest = %{exported_at: DateTime.utc_now() |> DateTime.to_iso8601(), version: 1}

      users = export_users()
      Mix.shell().info("  users: #{length(users)}")

      themes = export_themes()
      Mix.shell().info("  themes: #{length(themes)}")

      projects = export_projects()
      Mix.shell().info("  projects: #{length(projects)}")

      columns = export_columns()
      Mix.shell().info("  columns: #{length(columns)}")

      task_types = export_task_types()
      Mix.shell().info("  task_types: #{length(task_types)}")

      tasks = export_tasks()
      Mix.shell().info("  tasks: #{length(tasks)}")

      comments = export_task_comments()
      Mix.shell().info("  task_comments: #{length(comments)}")

      members = export_project_members()
      Mix.shell().info("  project_members: #{length(members)}")

      theme_prefs = export_project_theme_prefs()
      Mix.shell().info("  project_theme_prefs: #{length(theme_prefs)}")

      attachments = export_attachments()
      Mix.shell().info("  attachments: #{length(attachments)}")

      manifest =
        manifest
        |> Map.put(:users, length(users))
        |> Map.put(:themes, length(themes))
        |> Map.put(:projects, length(projects))
        |> Map.put(:columns, length(columns))
        |> Map.put(:task_types, length(task_types))
        |> Map.put(:tasks, length(tasks))
        |> Map.put(:task_comments, length(comments))
        |> Map.put(:project_members, length(members))
        |> Map.put(:project_theme_prefs, length(theme_prefs))
        |> Map.put(:attachments, length(attachments))

      write_json!(Path.join(tmp_dir, "manifest.json"), manifest)
      write_json!(Path.join(tmp_dir, "users.json"), users)
      write_json!(Path.join(tmp_dir, "themes.json"), themes)
      write_json!(Path.join(tmp_dir, "projects.json"), projects)
      write_json!(Path.join(tmp_dir, "columns.json"), columns)
      write_json!(Path.join(tmp_dir, "task_types.json"), task_types)
      write_json!(Path.join(tmp_dir, "tasks.json"), tasks)
      write_json!(Path.join(tmp_dir, "task_comments.json"), comments)
      write_json!(Path.join(tmp_dir, "project_members.json"), members)
      write_json!(Path.join(tmp_dir, "project_theme_prefs.json"), theme_prefs)
      write_json!(Path.join(tmp_dir, "attachments.json"), attachments)

      if include_files? do
        files_dir = Path.join(tmp_dir, "files")
        File.mkdir_p!(files_dir)
        download_s3_files!(attachments, files_dir)
      end

      zip_archive(tmp_dir, output_path)
      Mix.shell().info("Export complete: #{output_path}")
    after
      File.rm_rf(tmp_dir)
    end
  end

  defp export_users do
    Repo.all(
      from u in "users",
        select: %{
          id: u.id,
          email: u.email,
          confirmed_at: u.confirmed_at,
          role: u.role,
          display_name: u.display_name,
          avatar_key: u.avatar_key,
          theme_slug: u.theme_slug,
          theme_mode: u.theme_mode,
          is_agent: u.is_agent,
          agent_description: u.agent_description,
          agent_role: u.agent_role,
          agent_owner_id: u.agent_owner_id,
          inserted_at: u.inserted_at,
          updated_at: u.updated_at
        }
    )
  end

  defp export_themes do
    Repo.all(
      from t in "themes",
        select: %{
          id: t.id,
          slug: t.slug,
          name: t.name,
          palette_light: t.palette_light,
          palette_dark: t.palette_dark,
          inserted_at: t.inserted_at,
          updated_at: t.updated_at
        }
    )
  end

  defp export_projects do
    Repo.all(
      from p in "projects",
        select: %{
          id: p.id,
          slug: p.slug,
          name: p.name,
          description: p.description,
          owner_id: p.owner_id,
          avatar_key: p.avatar_key,
          background_key: p.background_key,
          public_link: p.public_link,
          theme_slug: p.theme_slug,
          agent_instructions: p.agent_instructions,
          inserted_at: p.inserted_at,
          updated_at: p.updated_at
        }
    )
  end

  defp export_columns do
    Repo.all(
      from c in "columns",
        select: %{
          id: c.id,
          project_id: c.project_id,
          name: c.name,
          rank: c.rank,
          description: c.description,
          color: c.color,
          inserted_at: c.inserted_at,
          updated_at: c.updated_at
        }
    )
  end

  defp export_task_types do
    Repo.all(
      from tt in "task_types",
        select: %{
          id: tt.id,
          project_id: tt.project_id,
          name: tt.name,
          color: tt.color,
          text_color: tt.text_color,
          description: tt.description,
          inserted_at: tt.inserted_at,
          updated_at: tt.updated_at
        }
    )
  end

  defp export_tasks do
    Repo.all(
      from t in "tasks",
        select: %{
          id: t.id,
          title: t.title,
          body_doc: t.body_doc,
          rank: t.rank,
          start_date: t.start_date,
          end_date: t.end_date,
          project_id: t.project_id,
          column_id: t.column_id,
          creator_id: t.creator_id,
          assignee_id: t.assignee_id,
          task_type_id: t.task_type_id,
          inserted_at: t.inserted_at,
          updated_at: t.updated_at
        }
    )
  end

  defp export_task_comments do
    Repo.all(
      from c in "task_comments",
        select: %{
          id: c.id,
          body: c.body,
          body_doc: c.body_doc,
          guest_name: c.guest_name,
          task_id: c.task_id,
          project_id: c.project_id,
          author_id: c.author_id,
          parent_id: c.parent_id,
          inserted_at: c.inserted_at,
          updated_at: c.updated_at
        }
    )
  end

  defp export_project_members do
    Repo.all(
      from m in "project_members",
        select: %{
          id: m.id,
          project_id: m.project_id,
          user_id: m.user_id,
          role: m.role,
          inserted_at: m.inserted_at,
          updated_at: m.updated_at
        }
    )
  end

  defp export_project_theme_prefs do
    Repo.all(
      from p in "project_theme_prefs",
        select: %{
          id: p.id,
          project_id: p.project_id,
          user_id: p.user_id,
          theme_slug: p.theme_slug,
          inserted_at: p.inserted_at,
          updated_at: p.updated_at
        }
    )
  end

  defp export_attachments do
    Repo.all(
      from a in "attachments",
        select: %{
          id: a.id,
          parent_type: a.parent_type,
          parent_id: a.parent_id,
          kind: a.kind,
          filename: a.filename,
          mime: a.mime,
          size: a.size,
          storage_key: a.storage_key,
          status: a.status,
          creator_id: a.creator_id,
          inserted_at: a.inserted_at,
          updated_at: a.updated_at
        }
    )
  end

  defp download_s3_files!(attachments, files_dir) do
    ready_attachments = Enum.filter(attachments, &(&1.status == "ready"))
    total = length(ready_attachments)

    if total > 0 do
      Mix.shell().info("  Downloading #{total} S3 files...")
    end

    ready_attachments
    |> Task.async_stream(
      fn attachment ->
        download_one_file!(attachment, files_dir)
      end,
      timeout: :infinity
    )
    |> Enum.each(fn
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> Mix.shell().error("  Failed to download: #{inspect(reason)}")
      {:exit, reason} -> Mix.shell().error("  Download crashed: #{inspect(reason)}")
    end)
  end

  defp download_one_file!(%{storage_key: key} = _attachment, files_dir) do
    dest = Path.join(files_dir, key)
    File.mkdir_p!(Path.dirname(dest))

    case ExAws.S3.get_object(Kaska.Storage.bucket(), key) |> ExAws.request() do
      {:ok, %{body: body}} ->
        File.write!(dest, body)
        :ok

      {:error, reason} ->
        {:error, {key, reason}}
    end
  end

  defp write_json!(path, data) do
    json = Jason.encode_to_iodata!(data, pretty: true)
    File.write!(path, json)
  end

  defp zip_archive(tmp_dir, output_path) do
    output_path |> Path.dirname() |> File.mkdir_p!()

    files =
      tmp_dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn file ->
        zip_entry = Path.relative_to(file, tmp_dir)
        {String.to_charlist(zip_entry), File.read!(file)}
      end)

    case :zip.create(files, [String.to_charlist(output_path)], [:memory]) do
      {:ok, {zip_binary, _file_list}} ->
        File.write!(output_path, zip_binary)

      {:error, reason} ->
        Mix.raise("Failed to create zip archive: #{inspect(reason)}")
    end
  end

  defp default_output_path do
    timestamp = DateTime.utc_now() |> DateTime.to_string() |> String.replace(~r/[:\s]/, "-")
    "kaska-export-#{timestamp}.zip"
  end

  defp parse_opts(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [output: :string, "no-files": :boolean]
      )

    opts
  end

  defp normalize_kv_args(args) do
    Enum.map(args, fn
      <<"output:", value::binary>> -> "--output=#{value}"
      <<"--no-files">> -> "--no-files"
      value -> value
    end)
  end
end
