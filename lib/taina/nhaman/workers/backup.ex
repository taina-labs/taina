defmodule Taina.Nhaman.Workers.Backup do
  @moduledoc """
  Backup agendado da instância (RFC 002, Fase 4). Roda pelo cron do Oban (ver
  `config :taina, Oban`) e delega a `Taina.Nhaman.Backup.run/1`.

  É **no-op enquanto o backup está desabilitado** (`config :taina, :backup,
  enabled: false`, o default) — a tarefa diária simplesmente retorna `:ok`. O
  admin/instalador liga via `BACKUP_ENABLED=true` + `BACKUP_DIR=…`.

  Uma falha vira `{:error, _}` para o Oban reagendar (até `max_attempts`); o
  destino de backup intermitente (USB desconectado) se recupera sozinho na
  próxima tentativa.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Taina.Nhaman.Backup

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    if Backup.enabled?() do
      do_backup()
    else
      :ok
    end
  end

  defp do_backup do
    case Backup.run() do
      {:ok, %{archive: path, bytes: bytes}} ->
        Logger.info("Backup concluído", path: path, bytes: bytes)
        :ok

      {:error, reason} = error ->
        Logger.error("Backup falhou", reason: inspect(reason))
        error
    end
  end
end
