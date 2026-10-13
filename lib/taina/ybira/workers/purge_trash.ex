defmodule Taina.Ybira.Workers.PurgeTrash do
  @moduledoc """
  Esvazia a lixeira do Ybira: apaga de vez os arquivos com `apagado_em` há mais
  de 30 dias e devolve a cota da Tekoa (ver `Taina.Ybira.purge_deleted_files/1`).

  Agendado por cron (todo dia às 03:00, em `config/config.exs`). Roda em nível de
  sistema, cruzando todas as Tekoas, por isso a lógica usa `skip_tekoa_id: true`.
  `unique` evita acúmulo de jobs idênticos numa mesma janela diária.
  """

  use Oban.Worker, queue: :default, unique: [period: 86_400]

  alias Taina.Ybira

  require Logger

  @cutoff_days 30
  @seconds_per_day 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.shift(DateTime.utc_now(), second: -@cutoff_days * @seconds_per_day)
    {:ok, purged} = Ybira.purge_deleted_files(cutoff)
    Logger.info("PurgeTrash: #{purged} arquivo(s) apagado(s) (cutoff #{DateTime.to_iso8601(cutoff)})")
    :ok
  end
end
