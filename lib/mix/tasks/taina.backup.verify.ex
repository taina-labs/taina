defmodule Mix.Tasks.Taina.Backup.Verify do
  @shortdoc "Round-trip real de backup → destruição → restore, com asserção"

  @moduledoc """
  Verifica que um backup gerado por `Taina.Nhaman.Backup` realmente restaura
  (RFC 002, Fase 4 — "restore testado automaticamente em CI").

  Faz um ciclo completo contra um **banco real** (não o sandbox de teste):

    1. semeia um marcador no banco (`maraca.tekoas`) e no storage;
    2. roda `Backup.run/1`;
    3. destrói os dados (apaga a linha e o storage);
    4. roda `Backup.restore/1`;
    5. confere que marcador de banco **e** de storage voltaram.

  Não sobe a árvore de supervisão da app (sem pool do Ecto, sem Oban): só carrega
  a config, sobe o `:postgrex` e fala direto com o banco — assim o
  `pg_restore --clean` não esbarra em planos em cache do pool.

  > ⚠️ **Destrutivo.** Roda contra o banco apontado por `Taina.Repo`/`DATABASE_URL`.
  > Use só em CI ou num banco descartável.

      MIX_ENV=dev mix taina.backup.verify
  """

  use Mix.Task

  alias Taina.Nhaman.Backup

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    uniq = System.unique_integer([:positive])
    storage = Path.join(System.tmp_dir!(), "taina_backup_verify_storage_#{uniq}")
    backup_dir = Path.join(System.tmp_dir!(), "taina_backup_verify_dir_#{uniq}")
    marker_rel = "verify/marker.txt"
    marker_path = Path.join(storage, marker_rel)
    token = "marker-#{uniq}"
    public_id = "verify_#{uniq}"

    File.mkdir_p!(Path.dirname(marker_path))
    File.write!(marker_path, token)

    {:ok, conn} = Postgrex.start_link(postgrex_opts())

    seed(conn, public_id)

    {:ok, %{archive: archive}} = Backup.run(dir: backup_dir, storage_root: storage)
    info("backup gerado: #{archive}")

    destroy(conn, public_id, storage)
    info("dados destruídos")

    {:ok, :restored} = Backup.restore(archive, storage_root: storage)
    info("restore concluído")

    assert_db_restored!(public_id)
    assert_storage_restored!(marker_path, token)

    File.rm_rf(storage)
    File.rm_rf(backup_dir)

    Mix.shell().info([:green, "✔ backup/restore round-trip OK", :reset])
  end

  defp seed(conn, public_id) do
    Postgrex.query!(
      conn,
      "INSERT INTO maraca.tekoas (name, public_id, inserted_at, updated_at) VALUES ($1, $2, now(), now())",
      ["backup-verify-#{public_id}", public_id]
    )
  end

  defp destroy(conn, public_id, storage) do
    Postgrex.query!(conn, "DELETE FROM maraca.tekoas WHERE public_id = $1", [public_id])
    File.rm_rf!(storage)
  end

  # Conexão nova: após `pg_restore --clean` os objetos foram recriados, então
  # consultamos com um cliente que não tem planos antigos em cache.
  defp assert_db_restored!(public_id) do
    {:ok, conn} = Postgrex.start_link(postgrex_opts())

    %{rows: [[count]]} =
      Postgrex.query!(conn, "SELECT count(*) FROM maraca.tekoas WHERE public_id = $1", [public_id])

    if count != 1 do
      Mix.raise("restore do banco falhou: tekoa marcador não voltou (count=#{count})")
    end
  end

  defp assert_storage_restored!(marker_path, token) do
    case File.read(marker_path) do
      {:ok, ^token} -> :ok
      other -> Mix.raise("restore do storage falhou: marcador ausente/divergente (#{inspect(other)})")
    end
  end

  defp postgrex_opts do
    uri = URI.parse(Backup.database_url())
    {user, pass} = parse_userinfo(uri.userinfo)

    [
      hostname: uri.host || "localhost",
      port: uri.port || 5432,
      username: user,
      password: pass,
      database: String.trim_leading(uri.path || "/postgres", "/")
    ]
  end

  defp parse_userinfo(nil), do: {"postgres", nil}

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {URI.decode(user), nil}
      [user, pass] -> {URI.decode(user), URI.decode(pass)}
    end
  end

  defp info(msg), do: Mix.shell().info("  " <> msg)
end
