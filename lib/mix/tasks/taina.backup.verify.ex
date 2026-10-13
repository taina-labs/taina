defmodule Mix.Tasks.Taina.Backup.Verify do
  @shortdoc "Round-trip real de backup → destruição → restore, com asserção"

  @moduledoc """
  Verifica que um backup gerado por `Taina.Nhaman.Backup` realmente restaura
  (RFC 002, Fase 4 — "restore testado automaticamente em CI").

  Faz um ciclo completo contra um **banco real** (não o sandbox de teste):

    1. semeia um marcador no banco (`maraca_mural`) e no storage;
    2. roda `Backup.run/1`;
    3. destrói os dados (apaga a linha e o storage);
    4. roda `Backup.restore/1`;
    5. confere que marcador de banco **e** de storage voltaram.

  Fala com o SQLite por conexões Exqlite próprias, sem subir a árvore de
  supervisão da app (sem pool do Ecto, sem Oban): o restore substitui o arquivo
  do banco inteiro, então nada dele pode estar aberto no processo.

  > **Destrutivo.** Roda contra o banco apontado por `Taina.Repo`/`DATABASE_PATH`.
  > Use só em CI ou num banco descartável.

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
    marker_rel = "verify/marker.txt"
    marker_path = Path.join(storage, marker_rel)
    token = "marker-#{uniq}"
    marker = "verify_#{uniq}"
    db_path = db_path()

    File.mkdir_p!(Path.dirname(marker_path))
    File.write!(marker_path, token)

    {:ok, conn} = Exqlite.Sqlite3.open(db_path)
    seed(conn, marker)

    {:ok, %{archive: archive}} = Backup.run(dir: backup_dir, storage_root: storage)
    info("backup gerado: #{archive}")

    destroy(conn, marker, storage)
    :ok = Exqlite.Sqlite3.close(conn)
    info("dados destruídos")

    {:ok, :restored} = Backup.restore(archive, storage_root: storage, database_path: db_path)
    info("restore concluído")

    assert_db_restored!(db_path, marker)
    assert_storage_restored!(marker_path, token)

    File.rm_rf(storage)
    File.rm_rf(backup_dir)

    Mix.shell().info([:green, "backup/restore round-trip OK", :reset])
  end

  # O marcador vai pro mural (append-only, N entradas por Tekoa). A Tekoa em si
  # e unica por box (`single_tekoa_enforcement`), entao reusamos a existente ou
  # criamos uma so quando o banco esta vazio (CI).
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

  # Conexão nova: o restore substituiu o arquivo do banco inteiro, então o
  # handle anterior não serve mais.
  defp assert_db_restored!(db_path, marker) do
    {:ok, conn} = Exqlite.Sqlite3.open(db_path)

    try do
      {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT count(*) FROM maraca_mural WHERE cid = ?")
      :ok = Exqlite.Sqlite3.bind(stmt, [marker])
      {:ok, [[count]]} = Exqlite.Sqlite3.fetch_all(conn, stmt)

      if count != 1 do
        Mix.raise("restore do banco falhou: marcador do mural nao voltou (count=#{count})")
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
      other -> Mix.raise("restore do storage falhou: marcador ausente/divergente (#{inspect(other)})")
    end
  end

  defp db_path do
    Application.fetch_env!(:taina, Taina.Repo)[:database] ||
      Mix.raise("Taina.Repo sem :database; aponte DATABASE_PATH para um arquivo SQLite")
  end

  defp exec!(conn, sql) do
    case Exqlite.Sqlite3.execute(conn, sql) do
      :ok -> :ok
      {:error, reason} -> Mix.raise("falha no SQLite: #{inspect(reason)} (#{sql})")
    end
  end

  defp info(msg), do: Mix.shell().info("  " <> msg)
end
