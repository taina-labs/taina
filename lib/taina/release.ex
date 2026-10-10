defmodule Taina.Release do
  @moduledoc """
  Tarefas executadas dentro do release (sem Mix disponível).

  Usado no boot do container (e no serviço systemd do módulo NixOS) para rodar
  migrações antes do servidor e preparar o papel de banco da aplicação:

      bin/taina eval "Taina.Release.migrate"
      bin/taina eval "Taina.Release.bootstrap_db"
  """

  @app :taina

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Cria o papel de aplicação (`taina_app`, sem superpoderes e sem bypass de RLS) e
  os grants que ele precisa, se ainda não existirem. É o único lugar onde o
  bootstrap do banco vive: o compose do Oka e o módulo NixOS chamam esta mesma
  tarefa, então o papel e os grants não saem de sincronia.

  A conexão vem das variáveis PG* (PGHOST, PGUSER, PGDATABASE); no NixOS é o
  socket local com autenticação peer, rodando como o usuário `postgres`. A senha
  do papel vem de TAINA_APP_PASSWORD e o nome dele de TAINA_APP_ROLE.

      bin/taina eval "Taina.Release.bootstrap_db"

  Idempotente: um papel que já existe é deixado como está.
  """
  def bootstrap_db do
    app_role = System.get_env("TAINA_APP_ROLE") || "taina_app"

    app_password =
      System.get_env("TAINA_APP_PASSWORD") ||
        raise "environment variable TAINA_APP_PASSWORD is missing"

    validate_identifier!(app_role)

    {:ok, conn} = Postgrex.start_link([])

    try do
      db_name = fetch_scalar!(conn, "SELECT current_database()")
      validate_identifier!(db_name)

      if role_exists?(conn, app_role) do
        IO.puts("papel #{app_role} já existe; seguindo sem alterar")
      else
        run!(
          conn,
          "CREATE ROLE #{app_role} LOGIN PASSWORD $1 NOSUPERUSER NOBYPASSRLS",
          [app_password]
        )
      end

      run!(conn, "GRANT CONNECT, CREATE ON DATABASE #{db_name} TO #{app_role}")
      run!(conn, "GRANT USAGE, CREATE ON SCHEMA public TO #{app_role}")
      :ok
    after
      if Process.alive?(conn), do: GenServer.stop(conn)
    end
  end

  defp role_exists?(conn, role) do
    fetch_scalar!(conn, "SELECT 1 FROM pg_roles WHERE rolname = $1", [role]) != nil
  end

  defp fetch_scalar!(conn, sql, params \\ []) do
    %Postgrex.Result{rows: rows} = Postgrex.query!(conn, sql, params)

    case rows do
      [[value] | _] -> value
      [] -> nil
    end
  end

  defp run!(conn, sql, params \\ []) do
    Postgrex.query!(conn, sql, params)
    :ok
  end

  # O papel e o nome do banco entram na SQL como identificadores, e um
  # identificador não pode ser parametrizado, então só aceitamos nomes simples.
  defp validate_identifier!(name) do
    if !Regex.match?(~r/^[a-z_][a-z0-9_]*$/i, name) do
      raise ArgumentError, "nome de identificador inválido: #{inspect(name)}"
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
