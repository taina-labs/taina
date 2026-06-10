defmodule Taina.Ybira.Workers.PurgeTrash do
  @moduledoc """
  Esvazia a lixeira do Ybira: apaga de vez os arquivos com `deleted_at` há mais
  de 30 dias e devolve a cota da Tekoa (ver `Taina.Ybira.purge_deleted_files/1`).

  Agendado por cron (todo dia às 03:00, em `config/config.exs`). Roda em nível de
  sistema, cruzando todas as Tekoas — por isso a lógica usa `skip_tekoa_id: true`.
  `unique` evita acúmulo de jobs idênticos numa mesma janela diária.
  """

  use Oban.Worker, queue: :default, unique: [period: 86_400]

  alias Taina.Ybira

  @cutoff_days 30
  @seconds_per_day 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(), -@cutoff_days * @seconds_per_day, :second)
    {:ok, _purged} = Ybira.purge_deleted_files(cutoff)
    :ok
  end
end
