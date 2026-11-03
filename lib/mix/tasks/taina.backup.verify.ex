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
    {:ok, _} = Application.ensure_all_started(:exqlite)

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
    File.write!(marker_path, token)
    File.write!(secret, "verify-secret-#{uniq}")
    File.chmod!(secret, 0o600)

    Application.put_env(:taina, :config, %{
      data_dir: System.tmp_dir!(),
      secret_key_base_file: secret
    })

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    seed(conn, marker)

    {:ok, %{archive: archive}} = Backup.run(dir: backup_dir, storage_root: storage)
    info("backup generated: #{archive}")

    destroy(conn, marker, storage)
    File.rm!(secret)
    :ok = Exqlite.Sqlite3.close(conn)
    info("data destroyed")

    {:ok, :restored} = Backup.restore(archive, storage_root: storage, database_path: db_path)
    info("restore completed")

    assert_db_restored!(db_path, marker)
    assert_storage_restored!(marker_path, token)
    assert_secret_restored!(secret, uniq)

    File.rm_rf(storage)
    File.rm_rf(backup_dir)
    File.rm(secret)

    Mix.shell().info([:green, "backup/restore round-trip OK", :reset])
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

        {:ok, id} = Exqlite.Sqlite3.last_insert_rowid(conn)
        id

      id ->
        id
    end
  end

  defp destroy(conn, marker, storage) do
    exec!(conn, "DELETE FROM maraca_mural WHERE cid = '#{marker}'")
    File.rm_rf!(storage)
  end

  defp assert_db_restored!(db_path, marker) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    try do
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM maraca_mural WHERE cid = ?")
      :ok = Exqlite.Sqlite3.bind(stmt, [marker])
      {:ok, [[count]]} = Exqlite.Sqlite3.fetch_all(conn, stmt)

      if count != 1 do
        Mix.raise("database restore failed: mural marker did not return (count=#{count})")
      end
    after
      Exqlite.Sqlite3.close(conn)
    end
  end

  defp query_one(conn, sql) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, [value]} -> value
      _ -> nil
    end
  end

  defp assert_storage_restored!(marker_path, token) do
    case File.read(marker_path) do
      {:ok, ^token} -> :ok
      other -> Mix.raise("storage restore failed: marker is missing or different (#{inspect(other)})")
    end
  end

  defp assert_secret_restored!(path, uniq) do
    case File.read(path) do
      {:ok, "verify-secret-" <> suffix} ->
        if suffix != Integer.to_string(uniq), do: Mix.raise("secret restore returned a different secret")

      other ->
        Mix.raise("secret restore failed: #{inspect(other)}")
    end
  end

  defp db_path do
    Application.fetch_env!(:taina, Taina.Repo)[:database] ||
      Mix.raise("Taina.Repo has no :database; point DATABASE_PATH at a SQLite file")
  end

  defp exec!(conn, sql) do
    case Exqlite.Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("SQLite failure: #{inspect(reason)} (#{sql})")
    end
  end

  defp info(msg), do: Mix.shell().info("  " <> msg)
end
