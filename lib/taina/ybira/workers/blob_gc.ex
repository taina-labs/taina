defmodule Taina.Ybira.Workers.BlobGc do
  @moduledoc """
  Processa a fila do GC diferido de blobs (`Taina.Ybira.BlobGc`): apaga do
  disco os bytes que nenhuma linha de `ybira_files` referencia mais, e derruba
  a fila; fila cujo blob voltou a viver (dedup) cai sem tocar nos bytes.

  Fecha a corrida do expurgo (revisão 0.1.0, item 1c) em duas cercas: a
  travessa local (`Taina.Ybira.BlobLock`) faz a conferência de referências e
  o apagão se excluírem do upload dos mesmos bytes (que grava os bytes antes
  de commitar a referência), e a graça de UMA hora entre o enfileiramento e
  a rodada cobre a janela em que um upload concorrente reanima o blob. O
  upload é raro frente à rodada e a seção crítica do GC é curta (uma
  consulta e um apagão): quem espera a vez, espera pouco.

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
