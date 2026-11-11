defmodule Taina.Release do
  @moduledoc """
  Tarefas executadas dentro do release (sem Mix disponível).

  Usado no boot do container (e no serviço systemd do módulo NixOS) para rodar
  migrações antes do servidor:

      bin/taina eval "Taina.Release.prepare"
  """

  @app :taina

  @doc "Creates a persistent secret with restrictive permissions, or reuses it."
  def ensure_secret!(path) do
    File.mkdir_p!(Path.dirname(path))

    # The release operator supplies the persistent secret path.
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    case File.open(path, [:write, :exclusive, :binary]) do
      {:ok, io} ->
        File.chmod!(path, 0o600)
        IO.binwrite(io, Base.encode64(:crypto.strong_rand_bytes(48)))
        File.close(io)
        :ok

      {:error, :eexist} ->
        File.chmod!(path, 0o600)
        :ok

      {:error, reason} ->
        raise "could not create secret key base: #{inspect(reason)}"
    end
  end

  def migrate do
    load_app()

    for repo <- repos() do
      case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true)) do
        {:ok, repo_pid, migrations} -> {:ok, repo_pid, migrations}
        {:error, reason} -> raise "migration failed: #{inspect(reason)}"
      end
    end
  end

  def prepare do
    settings = Application.get_env(@app, :config) || raise "Taina.Config was not loaded"
    data_dir = settings.data_dir
    storage_dir = settings.storage_dir
    backup_dir = settings.backup_dir
    File.mkdir_p!(data_dir)
    File.mkdir_p!(storage_dir)
    File.mkdir_p!(backup_dir)
    secret_path = settings.secret_key_base_file || Path.join(data_dir, "secret_key_base")
    ensure_secret!(secret_path)

    Application.put_env(
      @app,
      # Release boot intentionally updates the runtime endpoint configuration.
      # credo:disable-for-next-line OptimumCredo.Check.Warning.WebNamespaceInCore
      TainaWeb.Endpoint,
      # credo:disable-for-next-line OptimumCredo.Check.Warning.WebNamespaceInCore
      Keyword.put(Application.get_env(@app, TainaWeb.Endpoint, []), :secret_key_base, secret(secret_path))
    )

    migrate()
  end

  def rollback(repo, version) do
    load_app()

    case Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version)) do
      {:ok, repo_pid, migrations} -> {:ok, repo_pid, migrations}
      {:error, reason} -> raise "rollback failed: #{inspect(reason)}"
    end
  end

  defp load_app do
    Application.ensure_loaded(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp secret(path), do: path |> File.read!() |> String.trim()
end
