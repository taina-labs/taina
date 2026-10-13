defmodule Taina.CLI do
  @moduledoc """
  Verbos de operador dentro do release, chamados via `bin/taina eval`:

      bin/taina eval 'Taina.CLI.main(["doctor"])'
      bin/taina eval 'Taina.CLI.main(["backup", "--out", "/mnt/usb"])'
      bin/taina eval 'Taina.CLI.main(["restore", "/mnt/usb/taina-backup-20261013T040000Z.tar.gz"])'

  O `eval` carrega a aplicação mas não sobe a árvore de supervisão: cada verbo
  sobe só o que precisa (o app do NIF do SQLite), sem endpoint Phoenix e sem
  Oban. O acesso ao banco é SQLite direto via `Exqlite.Sqlite3`, à margem do
  pool do Repo, como `Taina.Nhaman.Backup`.

  ## Restore

  Destrutivo: o arquivo do banco é substituído pelo snapshot arquivado. É
  operação de drill/recuperação com a instância da caixa parada (o mesmo aviso
  de `Taina.Nhaman.Backup.restore/2`).

  ## Código de saída (congelado, o CLI do operador depende dele)

    * `0` - ok
    * `1` - falha de domínio (o verbo rodou e a operação falhou)
    * `2` - erro de uso (sem verbo, verbo desconhecido, flags incompletos)
    * `3` - falha de ambiente (config ausente, banco inacessível)

  ## Núcleo funcional / casca imperativa

  `parse/1` é puro (argv -> comando + opções). `run/1` é a única fronteira de
  IO e devolve o código sem encerrar o processo (é o que os testes exercitam);
  `main/1` encerra o processo com esse código.
  """

  alias Taina.Nhaman.Backup

  defstruct verb: nil, opts: []

  @type verb :: :backup | :restore | :doctor | :version
  @type t :: %__MODULE__{verb: verb(), opts: keyword()}
  @type exit_code :: 0 | 1 | 2 | 3

  @exit_ok 0
  @exit_domain_failure 1
  @exit_usage 2
  @exit_environment 3

  @usage """
  uso: taina <verbo> [opções]

  verbos:
    backup [--out DIR]        faz um backup da instância (.tar.gz) e imprime o caminho
    restore <arquivo.tar.gz>  restaura um backup; a instância da caixa deve estar parada
    doctor                    diagnóstico da caixa (só leitura, não muda nada)
    version                   imprime a versão do Tainá
  """

  @doc "Roda o verbo e encerra o processo com o código de saída."
  @spec main([String.t()]) :: no_return()
  def main(argv), do: System.halt(run(argv))

  @doc """
  Converte `argv` em comando (função pura, sem efeito).

  `{:error, :usage}` para argv vazio, verbo desconhecido ou flags incompletos.
  """
  @spec parse([String.t()]) :: {:ok, t()} | {:error, :usage}
  def parse(["backup"]), do: {:ok, %__MODULE__{verb: :backup}}
  def parse(["backup", "--out", dir]), do: {:ok, %__MODULE__{verb: :backup, opts: [dir: dir]}}
  def parse(["restore", archive]), do: {:ok, %__MODULE__{verb: :restore, opts: [archive: archive]}}
  def parse(["doctor"]), do: {:ok, %__MODULE__{verb: :doctor}}
  def parse(["version"]), do: {:ok, %__MODULE__{verb: :version}}
  def parse(_argv), do: {:error, :usage}

  @doc "Roda o verbo e devolve o código de saída, sem encerrar o processo."
  @spec run([String.t()]) :: exit_code()
  def run(argv) do
    case parse(argv) do
      {:ok, %__MODULE__{verb: :backup, opts: opts}} -> backup(opts)
      {:ok, %__MODULE__{verb: :restore, opts: opts}} -> restore(opts)
      {:ok, %__MODULE__{verb: :doctor}} -> doctor()
      {:ok, %__MODULE__{verb: :version}} -> version()
      {:error, :usage} -> usage()
    end
  end

  ## Verbos

  # O destino é decisão do CLI (flag ou config): sem o flag, ler a config aqui
  # em vez de depender do raise interno de Backup.run/1, porque config ausente
  # é ambiente quebrado (código 3) e não deve estourar como crash.
  defp backup(opts) do
    case backup_dir(opts[:dir]) do
      {:ok, dir} ->
        run_backup(dir)

      {:error, :no_dir} ->
        error("backup sem destino: passe --out DIR ou configure `config :taina, :backup, dir:`")
        @exit_environment
    end
  end

  defp backup_dir(dir) when is_binary(dir), do: {:ok, dir}

  defp backup_dir(nil) do
    case :taina |> Application.get_env(:backup, []) |> Keyword.get(:dir) do
      dir when is_binary(dir) -> {:ok, dir}
      _other -> {:error, :no_dir}
    end
  end

  defp run_backup(dir) do
    case start_sqlite() do
      :ok ->
        case Backup.run(dir: dir) do
          {:ok, %{archive: archive}} ->
            IO.puts(archive)
            @exit_ok

          {:error, reason} ->
            error("backup falhou: #{inspect(reason)}")
            @exit_domain_failure
        end

      {:error, reason} ->
        error("backup indisponível: #{inspect(reason)}")
        @exit_environment
    end
  end

  defp restore(opts) do
    case start_sqlite() do
      :ok ->
        case Backup.restore(opts[:archive]) do
          {:ok, :restored} ->
            IO.puts("restaurado: banco e armazenamento no estado do backup")
            @exit_ok

          {:error, reason} ->
            error("restore falhou: #{inspect(reason)}")
            @exit_domain_failure
        end

      {:error, reason} ->
        error("restore indisponível: #{inspect(reason)}")
        @exit_environment
    end
  end

  # Diagnóstico de leitura: linhas secas, uma por fato. Código 3 quando o
  # ambiente está quebrado (banco ou armazenamento inacessíveis); achados
  # operacionais (nenhum backup ainda, migração pendente) são informação,
  # não falha.
  defp doctor do
    IO.puts("versão: #{version_string()}")
    db_ok = doctor_db()
    storage_ok = doctor_storage()
    doctor_backup()
    doctor_migrations()

    if db_ok and storage_ok do
      @exit_ok
    else
      @exit_environment
    end
  end

  defp doctor_db do
    case repo_db_path() do
      {:ok, path} ->
        doctor_db(path)

      {:error, :no_config} ->
        IO.puts("banco de dados: config ausente (`config :taina, Taina.Repo, :database`)")
        false
    end
  end

  defp doctor_db(path) do
    case db_reachable?(path) do
      :ok ->
        IO.puts("banco de dados: #{path} (acessível)")
        true

      {:error, reason} ->
        IO.puts("banco de dados: #{path} (não acessível: #{inspect(reason)})")
        false
    end
  end

  # Abre o arquivo do banco à margem do pool do Repo (leitura pura; :readonly
  # não cria arquivo) e fecha em seguida: o que interessa é conseguir abrir.
  defp db_reachable?(path) do
    if File.exists?(path) do
      with {:ok, conn} <- open_readonly(path) do
        Exqlite.Sqlite3.close(conn)
        :ok
      end
    else
      {:error, :enoent}
    end
  end

  defp doctor_storage do
    case Application.get_env(:taina, :storage_root) do
      root when is_binary(root) ->
        storage_healthy?(root)

      _other ->
        IO.puts("armazenamento: config ausente (`config :taina, :storage_root`)")
        false
    end
  end

  defp storage_healthy?(root) do
    if File.dir?(root) do
      print_storage_line(root)
      true
    else
      IO.puts("armazenamento: #{root} (diretório não existe)")
      false
    end
  end

  defp print_storage_line(root) do
    case free_bytes(root) do
      {:ok, bytes} -> IO.puts("armazenamento: #{root} (#{format_bytes(bytes)} livres)")
      :error -> IO.puts("armazenamento: #{root} (espaço livre: desconhecido)")
    end
  end

  defp doctor_backup do
    enabled = if Backup.enabled?(), do: "habilitado", else: "desabilitado"
    IO.puts("backup: #{enabled}")
    IO.puts("último backup: #{last_backup_text()}")
  end

  defp last_backup_text do
    case Backup.last_backup() do
      {:ok, %{at: at, bytes: bytes}} -> "#{DateTime.to_iso8601(at)} (#{format_bytes(bytes)})"
      {:error, :none} -> "nenhum ainda"
      {:error, :no_dir} -> "sem destino configurado"
      {:error, :unreadable} -> "destino ilegível agora"
    end
  end

  defp doctor_migrations do
    case migrations_status() do
      {:ok, applied, pending} ->
        IO.puts("migrações: #{applied} aplicadas, #{pending} pendentes")

      {:error, reason} ->
        IO.puts("migrações: não foi possível ler (#{inspect(reason)})")
    end
  end

  # Aplicadas lidas da tabela do Ecto no banco, pendentes por diferença com os
  # arquivos de migração do app. Leitura à margem do Repo, como o Backup.
  defp migrations_status do
    with {:ok, path} <- repo_db_path(),
         {:ok, conn} <- open_readonly(path) do
      try do
        count_migrations(conn)
      after
        Exqlite.Sqlite3.close(conn)
      end
    end
  end

  defp count_migrations(conn) do
    with {:ok, stmt} <- Exqlite.Sqlite3.prepare(conn, "SELECT version FROM schema_migrations"),
         {:ok, rows} <- Exqlite.Sqlite3.fetch_all(conn, stmt),
         {:ok, available} <- migration_versions() do
      applied = MapSet.new(rows, fn [version] -> version end)
      pending = Enum.count(available, &(not MapSet.member?(applied, &1)))
      {:ok, MapSet.size(applied), pending}
    end
  end

  defp migration_versions do
    case File.ls(migrations_dir()) do
      {:ok, files} ->
        {:ok, for(file <- files, version = migration_version(file), do: version)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Só nomes `YYYYMMDDHHMMSS_descricao.exs` contam: outros arquivos no dir
  # (do editor ou de tooling) não são migração.
  defp migration_version(file) do
    case Regex.run(~r/^(\d+)_.+\.exs$/, file) do
      [_, version] -> String.to_integer(version)
      _other -> nil
    end
  end

  defp migrations_dir, do: Path.join(:code.priv_dir(:taina), "repo/migrations")

  defp version do
    IO.puts(version_string())
    @exit_ok
  end

  defp version_string, do: to_string(Application.spec(:taina, :vsn))

  ## Borda com o sistema

  defp usage do
    IO.puts(:stderr, @usage)
    @exit_usage
  end

  defp error(message), do: IO.puts(:stderr, message)

  # O `eval` carrega a aplicação sem startar: o app do NIF do SQLite pode não
  # estar no ar (o Repo não é started aqui). Start mínimo, sem supervision tree.
  defp start_sqlite do
    case Application.ensure_all_started(:exqlite) do
      {:ok, _apps} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp open_readonly(path) do
    with {:ok, _apps} <- Application.ensure_all_started(:exqlite) do
      Exqlite.Sqlite3.open(path, mode: [:readonly])
    end
  end

  # Espaço livre de verdade (o que sobra no disco, não a cota do app): lê o
  # `df -k` do sistema. Sem df na caixa, o diagnóstico diz "desconhecido" em
  # vez de mentir.
  defp free_bytes(path) do
    case System.find_executable("df") do
      nil ->
        :error

      df ->
        case System.cmd(df, ["-k", path]) do
          {output, 0} -> parse_free_bytes(output)
          {_output, _status} -> :error
        end
    end
  end

  # A última linha do `df -k` é a linha de dados; o campo "Available" é o
  # quarto (em blocos de 1K). Montagem estranha degrada para :error.
  defp parse_free_bytes(output) do
    with [line | _rest] <- output |> String.split("\n", trim: true) |> Enum.reverse(),
         [_fs, _blocks, _used, avail | _more] <- String.split(line, " ", trim: true),
         {kb, _rest} <- Integer.parse(avail) do
      {:ok, kb * 1024}
    else
      _other -> :error
    end
  end

  # Espelho de TainaWeb.CoreComponents.format_bytes/1 (convenção pt-BR, vírgula
  # decimal): o CLI não pode depender da camada web, então a cópia mora aqui.
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  defp format_bytes(bytes) do
    {value, unit} =
      cond do
        bytes >= 1024 ** 4 -> {bytes / 1024 ** 4, "TB"}
        bytes >= 1024 ** 3 -> {bytes / 1024 ** 3, "GB"}
        bytes >= 1024 ** 2 -> {bytes / 1024 ** 2, "MB"}
        true -> {bytes / 1024, "KB"}
      end

    text =
      if value >= 10 do
        value |> round() |> Integer.to_string()
      else
        value |> Float.round(1) |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ",")
      end

    "#{text} #{unit}"
  end

  defp repo_db_path do
    case Application.get_env(:taina, Taina.Repo) do
      config when is_list(config) ->
        case Keyword.get(config, :database) do
          path when is_binary(path) -> {:ok, path}
          _other -> {:error, :no_config}
        end

      _other ->
        {:error, :no_config}
    end
  end
end
