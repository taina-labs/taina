defmodule Taina.Ybira.Workers.BlobGc do
  @moduledoc """
  Processa a fila do GC diferido de blobs (`Taina.Ybira.BlobGc`): apaga do
  disco os bytes que nenhuma linha de `ybira_files` referencia mais, e derruba
  a fila; fila cujo blob voltou a viver (dedup) cai sem tocar nos bytes.

  Fecha a corrida do expurgo (revisão 0.1.0, item 1c): entre a conferência de
  referências e o apagão, um upload concorrente podia commitar um arquivo que
  compartilha o CID. A graça de UMA hora entre o enfileiramento e o
  processamento vence qualquer janela de upload; quem subiu dentro dela
  reanima o blob e a fila só registra o pleno.

  Agendado por cron (de hora em hora, em `config/config.exs`). Roda em nível
  de sistema, cruzando todas as Tekoas; o placar da rodada vai para o log.
  """

  use Oban.Worker, queue: :default

  alias Taina.Ybira

  require Logger

  # A graça: filas mais novas que isto não são processadas. Uma hora cobre
  # com folga a janela de dedup do expurgo (o upload que reanima o blob).
  @grace_seconds 3600

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.shift(DateTime.utc_now(), second: -@grace_seconds)
    {:ok, %{deleted: deleted, kept: kept}} = Ybira.gc_blobs(cutoff)

    Logger.info("BlobGc: #{deleted} blob(s) apagado(s), #{kept} fila(s) de blob vivo")

    :ok
  end
end
