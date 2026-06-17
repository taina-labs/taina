defmodule Taina.Nhaman.Backup do
  @moduledoc """
  Backup e restore da instância (RFC 002, Fase 4 — Nhaman-lite).

  Um backup é um único `.tar.gz` contendo:

    * `db.dump` — dump do PostgreSQL em formato custom (`pg_dump -Fc`), pronto
      para `pg_restore`;
    * `storage/…` — a árvore de arquivos do Ybira (`storage_root`).

  O destino (`dir`) é configurável — um disco USB montado, um remote sincronizado
  por rclone, etc. (`config :taina, :backup, dir: …`). Sem criptografia no MVP:
  off-site cifrado é o "Tainá Conecta" do pós-MVP (D10).

  ## Núcleo funcional / casca imperativa

  Os construtores de argumento (`pg_dump_args/2`, `pg_restore_args/2`,
  `database_url/0`, `archive_filename/1`) são puros e testáveis isoladamente. O
  empacotamento/extração (`package_archive/3`, `extract_archive/2`,
  `restore_storage/2`) usa só o `:erl_tar` da OTP — sem `tar` externo, bom para
  ARM. O dump/restore do banco delega para `pg_dump`/`pg_restore` via
  `System.cmd/3` — a única dependência de binário externo, coberta pela
  verificação de restore no CI (ver `mix taina.backup.verify`).

  `run/1` é exercido em produção pelo `Taina.Nhaman.Workers.Backup` (agendado) e
  pode ser disparado sob demanda ("backup com um clique").
  """

  @doc "O backup agendado está habilitado? (`config :taina, :backup, enabled:`)."
  def enabled?, do: Keyword.get(config(), :enabled, false)

  @doc """
  Roda um backup completo. Opções (todas com default sensato):

    * `:dir` — diretório destino do `.tar.gz` (default: config `:backup, :dir`)
    * `:storage_root` — árvore de arquivos a arquivar (default: config)
    * `:database_url` — conexão para o `pg_dump` (default: derivada do Repo)
    * `:now` — `DateTime` para o nome do arquivo (injetável em teste)

  Retorna `{:ok, %{archive: path, bytes: n}}` ou `{:error, reason}`.
  """
  def run(opts \\ []) do
    dir = Keyword.get(opts, :dir) || backup_dir()
    storage_root = Keyword.get(opts, :storage_root, storage_root())
    db_url = Keyword.get(opts, :database_url) || database_url()
    now = Keyword.get(opts, :now, DateTime.utc_now())

    with :ok <- File.mkdir_p(dir),
         {:ok, workdir} <- mk_workdir(),
         dump_path = Path.join(workdir, "db.dump"),
         :ok <- pg_dump(db_url, dump_path),
         archive_path = Path.join(dir, archive_filename(now)),
         :ok <- package_archive(archive_path, dump_path, storage_root) do
      _ = File.rm_rf(workdir)
      {:ok, %{archive: archive_path, bytes: file_size(archive_path)}}
    end
  end

  @doc """
  Restaura a instância a partir de um `.tar.gz` gerado por `run/1`.

  **Destrutivo:** `pg_restore --clean` derruba e recria os objetos do banco e o
  `storage_root` é substituído pela árvore arquivada. Use em drills e recuperação.

  Opções: `:storage_root`, `:database_url` (mesmos defaults de `run/1`).
  """
  def restore(archive_path, opts \\ []) do
    storage_root = Keyword.get(opts, :storage_root, storage_root())
    db_url = Keyword.get(opts, :database_url) || database_url()

    with {:ok, workdir} <- mk_workdir(),
         :ok <- extract_archive(archive_path, workdir),
         :ok <- pg_restore(db_url, Path.join(workdir, "db.dump")),
         :ok <- restore_storage(Path.join(workdir, "storage"), storage_root) do
      _ = File.rm_rf(workdir)
      {:ok, :restored}
    end
  end

  ## Empacotamento (OTP :erl_tar — sem binário externo)

  @doc """
  Monta o `.tar.gz` com `db.dump` + a árvore de `storage_root` sob `storage/`.
  Adiciona apenas arquivos (diretórios vazios são irrelevantes para o storage),
  com caminhos relativos determinísticos.
  """
  def package_archive(archive_path, dump_path, storage_root) do
    entries = [{~c"db.dump", String.to_charlist(dump_path)} | storage_entries(storage_root)]

    case :erl_tar.create(String.to_charlist(archive_path), entries, [:compressed]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:archive_failed, reason}}
    end
  end

  @doc "Extrai um `.tar.gz` em `dest` (criado se necessário)."
  def extract_archive(archive_path, dest) do
    :ok = File.mkdir_p(dest)

    case :erl_tar.extract(String.to_charlist(archive_path), [
           :compressed,
           {:cwd, String.to_charlist(dest)}
         ]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:extract_failed, reason}}
    end
  end

  @doc """
  Coloca a árvore de storage extraída em `storage_root`, substituindo o conteúdo
  anterior. `rm_rf` antes do `cp_r` garante reposição limpa (sem `storage_root`
  preexistente, `cp_r` copia a origem *como* o destino — semântica de merge
  total que queremos num restore).
  """
  def restore_storage(extracted_storage, storage_root) do
    if File.dir?(extracted_storage) do
      File.rm_rf!(storage_root)

      case File.cp_r(extracted_storage, storage_root) do
        {:ok, _} -> :ok
        {:error, reason, _path} -> {:error, {:storage_restore_failed, reason}}
      end
    else
      # Backup sem nenhum arquivo no storage — nada a repor.
      :ok
    end
  end

  ## Construtores puros (testáveis isoladamente)

  @doc "Nome do arquivo de backup para um instante (UTC): `taina-backup-<stamp>.tar.gz`."
  def archive_filename(%DateTime{} = now) do
    stamp = now |> DateTime.truncate(:second) |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    "taina-backup-#{stamp}.tar.gz"
  end

  @doc "Argumentos do `pg_dump` (formato custom, portável)."
  def pg_dump_args(db_url, dump_path) do
    [
      "--format=custom",
      "--no-owner",
      "--no-privileges",
      "--file=#{dump_path}",
      "--dbname=#{db_url}"
    ]
  end

  @doc "Argumentos do `pg_restore` (limpa o destino antes de recarregar)."
  def pg_restore_args(db_url, dump_path) do
    [
      "--clean",
      "--if-exists",
      "--no-owner",
      "--no-privileges",
      "--dbname=#{db_url}",
      dump_path
    ]
  end

  @doc """
  URL de conexão `postgresql://…` derivada da config do `Taina.Repo` (usa `:url`
  quando presente, senão monta a partir dos campos discretos). Consumida pelo
  `pg_dump`/`pg_restore`.
  """
  def database_url do
    config = Application.fetch_env!(:taina, Taina.Repo)

    case config[:url] do
      url when is_binary(url) -> url
      _ -> build_url(config)
    end
  end

  defp build_url(config) do
    user = config[:username] || "postgres"
    pass = config[:password] || ""
    host = config[:hostname] || "localhost"
    port = config[:port] || 5432
    db = config[:database] || raise "Taina.Repo sem :database nem :url para o backup"

    userinfo =
      if pass == "", do: URI.encode(user), else: "#{URI.encode(user)}:#{URI.encode(pass)}"

    "postgresql://#{userinfo}@#{host}:#{port}/#{db}"
  end

  ## Casca imperativa

  defp pg_dump(db_url, dump_path), do: run_cmd("pg_dump", pg_dump_args(db_url, dump_path))
  defp pg_restore(db_url, dump_path), do: run_cmd("pg_restore", pg_restore_args(db_url, dump_path))

  defp run_cmd(bin, args) do
    case System.cmd(bin, args, stderr_to_stdout: true) do
      {_out, 0} -> :ok
      {out, code} -> {:error, {:command_failed, bin, code, String.slice(out, 0, 2_000)}}
    end
  rescue
    e in ErlangError -> {:error, {:command_unavailable, bin, e.original}}
  end

  defp storage_entries(storage_root) do
    if File.dir?(storage_root) do
      storage_root
      |> all_files()
      |> Enum.map(fn abs ->
        rel = Path.relative_to(abs, storage_root)
        {String.to_charlist(Path.join("storage", rel)), String.to_charlist(abs)}
      end)
    else
      []
    end
  end

  defp all_files(dir) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn entry ->
      path = Path.join(dir, entry)
      if File.dir?(path), do: all_files(path), else: [path]
    end)
  end

  defp mk_workdir do
    path = Path.join(System.tmp_dir!(), "taina_backup_#{System.unique_integer([:positive])}")

    case File.mkdir_p(path) do
      :ok -> {:ok, path}
      error -> error
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp config, do: Application.get_env(:taina, :backup, [])

  defp backup_dir do
    Keyword.get(config(), :dir) ||
      raise "backup sem destino: configure `config :taina, :backup, dir: …` (ou BACKUP_DIR)"
  end

  defp storage_root, do: Application.fetch_env!(:taina, :storage_root)
end
