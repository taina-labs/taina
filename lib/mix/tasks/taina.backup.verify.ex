defmodule Mix.Tasks.Taina.Backup.Verify do
  @shortdoc "Verify a real backup, destruction and restore round trip"

  @moduledoc """
  Exercises a complete backup and restore cycle against a real, disposable
  SQLite database. This task is destructive and belongs only in development
  and CI. It is not part of the release operator API.

      MIX_ENV=dev mix taina.backup.verify
  """

  use Mix.Task

  alias Taina.Nhaman.Backup

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    case Application.ensure_all_started(:exqlite) do
      {:ok, _apps} -> :ok
      {:error, reason} -> Mix.raise("could not start SQLite: #{inspect(reason)}")
    end

    uniq = System.unique_integer([:positive])
    storage = Path.join(System.tmp_dir!(), "taina_backup_verify_storage_#{uniq}")
    backup_dir = Path.join(System.tmp_dir!(), "taina_backup_verify_dir_#{uniq}")
    secret = Path.join(System.tmp_dir!(), "taina_backup_verify_secret_#{uniq}")
    marker_rel = "verify/marker.txt"
    marker_path = Path.join(storage, marker_rel)
    token = "marker-#{uniq}"
    marker = "verify_#{uniq}"
    db_path = db_path()

    File.mkdir_p!(Path.dirname(marker_path))
    # The marker lives under the server-generated temporary storage directory.
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    File.write!(marker_path, token)
    File.write!(secret, "verify-secret-#{uniq}")
    File.chmod!(secret, 0o600)

    Application.put_env(:taina, :config, %{
      data_dir: System.tmp_dir!(),
      secret_key_base_file: secret
    })

    conn = open!(db_path)
    seed(conn, marker)

    archive =
      case Backup.run(dir: backup_dir, storage_root: storage) do
        {:ok, %{archive: archive}} -> archive
        {:error, reason} -> Mix.raise("backup generation failed: #{inspect(reason)}")
      end

    info("backup generated: #{archive}")

    destroy(conn, marker, storage)
    File.rm!(secret)
    _ = Exqlite.Sqlite3.close(conn)
    info("data destroyed")

    case Backup.restore(archive, storage_root: storage, database_path: db_path) do
      {:ok, :restored} -> :ok
      {:error, reason} -> Mix.raise("backup restore failed: #{inspect(reason)}")
    end

    info("restore completed")

    assert_db_restored!(db_path, marker)
    assert_storage_restored!(marker_path, token)
    assert_secret_restored!(secret, uniq)

    File.rm_rf(storage)
    File.rm_rf(backup_dir)
    File.rm(secret)

    Mix.shell().info([:green, "backup/restore round-trip OK", :reset])
  end

  defp assert_db_restored!(db_path, marker) do
    conn = open!(db_path)

    try do
      stmt = prepare!(conn, "SELECT count(*) FROM maraca_mural WHERE cid = ?")
      expect_ok(Exqlite.Sqlite3.bind(stmt, [marker]), "bind mural marker")
      count = restored_marker_count(fetch_all!(conn, stmt))

      if count != 1 do
        Mix.raise("database restore failed: mural marker did not return (count=#{count})")
      end
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  defp assert_secret_restored!(path, uniq) do
    # The verification secret lives at the server-generated temporary path.
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    case File.read(path) do
      {:ok, "verify-secret-" <> suffix} ->
        if suffix != Integer.to_string(uniq), do: Mix.raise("secret restore returned a different secret")

      other ->
        Mix.raise("secret restore failed: #{inspect(other)}")
    end
  end

  defp assert_storage_restored!(marker_path, token) do
    # The marker lives under the server-generated temporary storage directory.
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    case File.read(marker_path) do
      {:ok, ^token} -> :ok
      other -> Mix.raise("storage restore failed: marker is missing or different (#{inspect(other)})")
    end
  end

  defp db_path do
    :taina
    |> Application.fetch_env!(Taina.Repo)
    |> Keyword.get(:database) ||
      Mix.raise("Taina.Repo has no :database; point DATABASE_PATH at a SQLite file")
  end

  defp destroy(conn, marker, storage) do
    exec!(conn, "DELETE FROM maraca_mural WHERE cid = '#{marker}'")
    File.rm_rf!(storage)
  end

  defp exec!(conn, sql) do
    case Exqlite.Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("SQLite failure: #{inspect(reason)} (#{sql})")
    end
  end

  defp expect_ok({:ok, value}, _operation), do: value
  defp expect_ok(:ok, _operation), do: :ok

  defp expect_ok({:error, reason}, operation) do
    Mix.raise("#{operation} failed: #{inspect(reason)}")
  end

  defp fetch_all!(conn, stmt), do: expect_ok(Exqlite.Sqlite3.fetch_all(conn, stmt), "fetch SQLite query")

  defp info(message), do: Mix.shell().info("  " <> message)

  defp open!(path), do: expect_ok(Exqlite.Sqlite3.open(path), "open SQLite database")

  defp prepare!(conn, sql), do: expect_ok(Exqlite.Sqlite3.prepare(conn, sql), "prepare SQLite query")

  defp query_one(conn, sql) do
    stmt = prepare!(conn, sql)

    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [value]} -> value
      :done -> nil
      {:error, reason} -> Mix.raise("SQLite query failed: #{inspect(reason)}")
      other -> Mix.raise("unexpected SQLite query result: #{inspect(other)}")
    end
  end

  defp restored_marker_count([[count]]), do: count

  defp restored_marker_count(rows) do
    Mix.raise("database restore returned an unexpected marker result: #{inspect(rows)}")
  end

  defp seed(conn, marker) do
    now = "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"
    seq = System.unique_integer([:positive])

    exec!(conn, """
    INSERT INTO maraca_mural (seq, tipo, payload, signature, cid, tekoa_id, inserted_at)
    VALUES (#{seq}, 'verify', '{}', x'00', '#{marker}', #{tekoa_id(conn)}, #{now})
    """)
  end

  defp tekoa_id(conn) do
    case query_one(conn, "SELECT id FROM maraca_tekoas LIMIT 1") do
      nil ->
        now = "strftime('%Y-%m-%dT%H:%M:%SZ', 'now')"

        exec!(conn, """
        INSERT INTO maraca_tekoas (name, domain, public_id, inserted_at, updated_at)
        VALUES ('backup-verify', 'backup-verify.local', 'backup_verify', #{now}, #{now})
        """)

        expect_ok(Exqlite.Sqlite3.last_insert_rowid(conn), "read inserted Tekoa id")

      id ->
        id
    end
  end
end
