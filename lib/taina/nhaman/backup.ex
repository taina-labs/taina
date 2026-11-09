defmodule Taina.Nhaman.Backup do
  @moduledoc """
  Backup e restore da instância (RFC 002, Fase 4 — Nhaman-lite).

  Um backup é um único `.tar.gz` contendo:

    * `db.dump` — snapshot do SQLite (`VACUUM INTO`), um arquivo de banco
      standalone e completo;
    * `storage/…` — a árvore de arquivos do Ybira (`storage_root`).

  O destino (`dir`) é configurável — um disco USB montado, um remote sincronizado
  por rclone, etc. (`config :taina, :backup, dir: …`). Sem criptografia no MVP:
  off-site cifrado é o "Tainá Conecta" do pós-MVP (D10).

  ## Núcleo funcional / casca imperativa

  Os helpers puros (`archive_filename/1`, `parse_archive_filename/1`,
  `package_archive/3`, `extract_archive/2`, `restore_storage/2`) são testáveis
  isoladamente e o empacotamento usa só o `:erl_tar` da OTP — sem binário
  externo, bom para ARM. O snapshot do banco abre o arquivo SQLite com
  `Exqlite.Sqlite3` direto (à margem do pool do Repo) e roda `VACUUM INTO`, que
  lê o banco vivo numa transação de leitura e grava uma cópia standalone: o
  backup roda com a instância no ar. O restore substitui o arquivo do banco
  inteiro, então é operação de drill/recuperação com o app da caixa parado.

  `run/1` é exercido em produção pelo `Taina.Nhaman.Workers.Backup` (agendado) e
  pode ser disparado sob demanda ("backup com um clique").
  """

  @doc "O backup agendado está habilitado? (`config :taina, :backup, enabled:`)."
  def enabled?, do: Keyword.get(config(), :enabled, false)

  @doc """
  O último backup que terminou bem: o `.tar.gz` mais recente no destino
  (`config :taina, :backup, dir:`), lido direto do disco, sem tabela de
  histórico. `run/1` só grava o arquivo no final, então arquivo presente é o
  registro do backup que deu certo (tela "Saúde da comunidade").

  ## Retorno

    * `{:ok, %{at: DateTime, bytes: non_neg_integer}}` - quando e quanto guardou
    * `{:error, :none}` - nenhum backup ainda
    * `{:error, :no_dir}` - destino não configurado
    * `{:error, :unreadable}` - destino configurado mas ilegível agora (USB
      desconectado e afins)
  """
  def last_backup do
    case Keyword.get(config(), :dir) do
      nil ->
        {:error, :no_dir}

      dir ->
        case File.ls(dir) do
          {:ok, entries} ->
            latest_archive(entries, dir)

          # Destino nunca criado: instalação nova, não há backups (enoent).
          # Outras falhas (permissão, disco) são ilegíveis agora, não "vazio".
          {:error, :enoent} ->
            {:error, :none}

          {:error, _reason} ->
            {:error, :unreadable}
        end
    end
  end

  # O mais recente entre os arquivos de backup válidos; nomes estranhos no
  # destino (destino compartilhado) são ignorados, não derrubam a leitura.
  defp latest_archive(entries, dir) do
    entries
    |> Enum.map(fn name -> {name, parse_archive_filename(name)} end)
    |> Enum.filter(fn {_name, parsed} -> match?({:ok, _at}, parsed) end)
    |> case do
      [] ->
        {:error, :none}

      valid ->
        {name, {:ok, at}} = Enum.max_by(valid, fn {_name, {:ok, at}} -> at end)
        {:ok, %{at: at, bytes: file_size(Path.join(dir, name))}}
    end
  end

  @doc """
  Roda um backup completo. Opções (todas com default sensato):

    * `:dir` — diretório destino do `.tar.gz` (default: config `:backup, :dir`)
    * `:storage_root` — árvore de arquivos a arquivar (default: config)
    * `:database_path` — arquivo SQLite a copiar (default: config do Repo)
    * `:now` — `DateTime` para o nome do arquivo (injetável em teste)

  Retorna `{:ok, %{archive: path, bytes: n}}` ou `{:error, reason}`.
  """
  def run(opts \\ []) do
    dir = Keyword.get(opts, :dir) || backup_dir()
    storage_root = Keyword.get(opts, :storage_root, storage_root())
    db_path = Keyword.get(opts, :database_path) || repo_db_path()
    now = Keyword.get(opts, :now, DateTime.utc_now())
    workdir = tmp_workdir()
    secret = secret_path()

    try do
      with :ok <- validate_secret(secret),
           :ok <- File.mkdir_p(dir),
           :ok <- File.mkdir_p(workdir),
           dump_path = Path.join(workdir, "db.dump"),
           :ok <- snapshot_db(db_path, dump_path),
           archive_path = Path.join(dir, archive_filename(now)),
           :ok <- package_archive(archive_path, dump_path, storage_root, secret) do
        {:ok, %{archive: archive_path, bytes: file_size(archive_path)}}
      end
    after
      File.rm_rf(workdir)
    end
  end

  @doc """
  Restaura a instância a partir de um `.tar.gz` gerado por `run/1`.

  **Destrutivo:** o arquivo do banco é substituído pelo snapshot arquivado e o
  `storage_root` recebe a árvore arquivada. Como a instância mantém o banco
  aberto, o restore é operação de drill/recuperação com o app da caixa parado.

  Opções: `:storage_root`, `:database_path` (mesmos defaults de `run/1`).
  """
  def restore(archive_path, opts \\ []) do
    storage_root = Keyword.get(opts, :storage_root, storage_root())
    db_path = Keyword.get(opts, :database_path) || repo_db_path()
    workdir = tmp_workdir()

    try do
      with :ok <- extract_archive(archive_path, workdir),
           :ok <- validate_restore_contents(workdir),
           :ok <- restore_db(Path.join(workdir, "db.dump"), db_path),
           :ok <- restore_storage(Path.join(workdir, "storage"), storage_root),
           :ok <- restore_secret(Path.join(workdir, "secret_key_base"), secret_path()) do
        {:ok, :restored}
      end
    after
      File.rm_rf(workdir)
    end
  end

  ## Empacotamento (OTP :erl_tar — sem binário externo)

  @doc """
  Monta o `.tar.gz` com `db.dump`, `secret_key_base` e a árvore de `storage_root`
  sob `storage/`. Adiciona apenas arquivos (diretórios vazios são irrelevantes
  para o storage), com caminhos relativos determinísticos.
  """
  def package_archive(archive_path, dump_path, storage_root) do
    package_archive(archive_path, dump_path, storage_root, nil)
  end

  def package_archive(archive_path, dump_path, storage_root, secret_path) do
    with :ok <- validate_secret(secret_path) do
      entries = [
        {~c"db.dump", String.to_charlist(dump_path)},
        {~c"secret_key_base", String.to_charlist(secret_path)}
        | storage_entries(storage_root)
      ]

      case :erl_tar.create(String.to_charlist(archive_path), entries, [:compressed]) do
        :ok -> :ok
        {:error, reason} -> {:error, {:archive_failed, reason}}
      end
    end
  end

  @doc "Extrai um `.tar.gz` em `dest` (criado se necessário)."
  def extract_archive(archive_path, dest) do
    :ok = File.mkdir_p(dest)

    with {:ok, names} <- :erl_tar.table(String.to_charlist(archive_path), [:compressed]),
         :ok <- safe_members(names) do
      extract(archive_path, dest)
    end
  end

  defp extract(archive_path, dest) do
    case :erl_tar.extract(String.to_charlist(archive_path), [
           :compressed,
           {:cwd, String.to_charlist(dest)}
         ]) do
      :ok -> :ok
      {:error, reason} -> {:error, {:extract_failed, reason}}
    end
  end

  defp safe_members(names) do
    members = Enum.map(names, &to_string/1)

    if "db.dump" in members and Enum.all?(members, &safe_member?/1), do: :ok, else: {:error, :unsafe_archive}
  end

  defp validate_restore_contents(workdir) do
    if File.regular?(Path.join(workdir, "db.dump")) do
      validate_secret(Path.join(workdir, "secret_key_base"))
    else
      {:error, :missing_database}
    end
  end

  defp safe_member?(name) do
    not String.starts_with?(name, "/") and ".." not in Path.split(name) and
      (name in ["db.dump", "secret_key_base"] or String.starts_with?(name, "storage/"))
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

  defp restore_secret(path, destination) do
    if File.regular?(path) do
      with :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(path, destination),
           :ok <- File.chmod(destination, 0o600) do
        validate_secret(destination)
      end
    else
      {:error, :missing_secret}
    end
  end

  defp validate_secret(path) when is_binary(path) do
    if File.regular?(path) do
      case File.read(path) do
        {:ok, secret} -> if(String.trim(secret) == "", do: {:error, :invalid_secret}, else: :ok)
        {:error, _reason} -> {:error, :missing_secret}
      end
    else
      {:error, :missing_secret}
    end
  end

  defp validate_secret(_path), do: {:error, :missing_secret}

  ## Construtores puros (testáveis isoladamente)

  @doc "Nome do arquivo de backup para um instante (UTC): `taina-backup-<stamp>.tar.gz`."
  def archive_filename(%DateTime{} = now) do
    stamp = now |> DateTime.truncate(:second) |> Calendar.strftime("%Y%m%dT%H%M%SZ")
    "taina-backup-#{stamp}.tar.gz"
  end

  @doc """
  Extrai o instante (UTC) codado no nome de arquivo gerado por `archive_filename/1`.

  Lê "quando foi o último backup" direto do destino, sem banco de dados de
  histórico: `last_backup/0` lista o diretório e decodifica os nomes.
  """
  def parse_archive_filename("taina-backup-" <> rest) do
    with [stamp, "tar.gz"] <- String.split(rest, ".", parts: 2),
         {:ok, datetime} <- stamp_to_datetime(stamp) do
      {:ok, datetime}
    else
      _ -> :error
    end
  end

  def parse_archive_filename(_other), do: :error

  # O stamp é o `%Y%m%dT%H%M%SZ` de `archive_filename/1`, sempre UTC (sufixo Z).
  defp stamp_to_datetime(stamp) do
    case Regex.run(~r/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/, stamp) do
      [_, y, mo, d, h, mi, s] ->
        with {:ok, date} <- Date.new(int(y), int(mo), int(d)),
             {:ok, time} <- Time.new(int(h), int(mi), int(s)) do
          DateTime.new(date, time, "Etc/UTC")
        end

      nil ->
        :error
    end
  end

  defp int(part), do: String.to_integer(part)

  ## Banco (SQLite, à margem do pool do Repo)

  defp repo_db_path do
    Application.fetch_env!(:taina, Taina.Repo)[:database] ||
      raise "backup sem banco: Taina.Repo sem :database (passe :database_path)"
  end

  # O VACUUM INTO exige destino inexistente e grava um banco standalone: uma
  # leitura do arquivo atual, feita por conexão efêmera. O busy_timeout cobre
  # um escritor do app em curso (mesmo motivo do config do Repo).
  defp snapshot_db(db_path, dump_path) do
    with :ok <- rm_if_exists(dump_path),
         {:ok, conn} <- open_db(db_path) do
      try do
        vacuum_into(conn, dump_path)
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  defp open_db(db_path) do
    # Sem :create: o banco desaparecido é erro, não um snapshot vazio.
    case Exqlite.Sqlite3.open(db_path, mode: [:readwrite]) do
      {:ok, conn} ->
        Exqlite.Sqlite3.set_busy_timeout(conn, 5_000)
        {:ok, conn}

      {:error, reason} ->
        {:error, {:sqlite_failed, reason}}
    end
  end

  defp vacuum_into(conn, dump_path) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, "VACUUM INTO ?"),
         :ok <- Exqlite.Sqlite3.bind(stmt, [dump_path]) do
      case Exqlite.Sqlite3.step(conn, stmt) do
        :done -> :ok
        :busy -> {:error, {:sqlite_failed, :busy}}
        {:error, reason} -> {:error, {:sqlite_failed, reason}}
      end
    end
  end

  # Substitui o arquivo do banco pelo snapshot. Os siblings -wal/-shm do banco
  # vivo ficam obsoletos depois da troca: apontam para páginas que o snapshot
  # não tem.
  defp restore_db(dump_path, db_path) do
    with :ok <- rm_if_exists(db_path <> "-wal"),
         :ok <- rm_if_exists(db_path <> "-shm"),
         :ok <- rm_if_exists(db_path) do
      File.cp(dump_path, db_path)
    end
  end

  defp rm_if_exists(path) do
    case File.rm(path) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, {:sqlite_failed, reason}}
    end
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

  defp tmp_workdir do
    Path.join(System.tmp_dir!(), "taina_backup_#{System.unique_integer([:positive])}")
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

  defp secret_path do
    settings = Application.get_env(:taina, :config, %{})
    Map.get(settings, :secret_key_base_file) || Path.join(Map.get(settings, :data_dir, "/app/data"), "secret_key_base")
  end
end
