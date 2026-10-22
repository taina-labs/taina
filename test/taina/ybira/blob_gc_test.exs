defmodule Taina.Ybira.Workers.BlobGcTest do
  # `async: false`: o teste de corrida sobe tarefas (uploads + GC) em outros
  # processos, que so usam a conexao do sandbox em modo compartilhado.
  use Taina.DataCase, async: false

  import Taina.Fixtures

  alias Taina.Ybira
  # A fila (schema) e o worker compartilham o nome; o worker fica com ele.
  alias Taina.Ybira.BlobGc, as: Queue
  alias Taina.Ybira.Workers.BlobGc
  alias Ypy.Ybira.File, as: YbiraFile

  @seconds_per_day 86_400
  @seconds_per_hour 3600

  test "deletes an unreferenced blob after the grace and drops the row" do
    scope = scope_fixture()
    file = upload_and_purge(scope, "sozinho")

    assert blob_on_disk?(file)
    assert Ybira.blob_referenced?(file.blob_cid) == false

    # A graça de uma hora: fila recém-enfileirada não é processada.
    assert :ok = BlobGc.perform(%Oban.Job{args: %{}})
    assert blob_on_disk?(file)
    assert queue_row?(file.blob_cid)

    # Vencida a graça, os bytes saem do disco e a fila cai.
    backdate_enqueue(file.blob_cid, hours_ago(2))

    assert :ok = BlobGc.perform(%Oban.Job{args: %{}})
    refute blob_on_disk?(file)
    refute queue_row?(file.blob_cid)
  end

  test "keeps a blob that a live file still references, and drops the row" do
    scope = scope_fixture()
    {:ok, a} = Ybira.upload(scope, tmp_upload_fixture("iguais", "a.txt"))
    {:ok, b} = Ybira.upload(scope, tmp_upload_fixture("iguais", "b.txt"))

    # Endereçado por conteúdo: os mesmos bytes, mesmo CID, mesmo caminho.
    assert a.blob_cid == b.blob_cid

    {:ok, _} = Ybira.delete_file(scope, a.rkey)
    backdate_apagado_em(a.id, days_ago(31))
    {:ok, 1} = Ybira.purge_deleted_files(days_ago(30))

    # b segue vivo e referencia o mesmo blob: o GC derruba a fila e mantem
    # os bytes.
    backdate_enqueue(a.blob_cid, hours_ago(2))

    assert :ok = BlobGc.perform(%Oban.Job{args: %{}})
    assert Repo.get(YbiraFile, b.id, skip_tekoa_id: true)
    assert blob_on_disk?(b)
    refute queue_row?(a.blob_cid)
  end

  test "a dedup'd blob survives while any row references it, even past the grace" do
    scope = scope_fixture()
    a = upload_and_purge(scope, "iguais")

    # O upload concorrente dentro da janela: mesmos bytes, mesmo CID, o blob
    # voltou a viver. O GC derruba a fila e NAO apaga os bytes.
    {:ok, c} = Ybira.upload(scope, tmp_upload_fixture("iguais", "c.txt"))
    assert c.blob_cid == a.blob_cid

    backdate_enqueue(a.blob_cid, hours_ago(2))

    assert :ok = BlobGc.perform(%Oban.Job{args: %{}})
    assert blob_on_disk?(c)
    refute queue_row?(a.blob_cid)
  end

  test "a GC round racing same-bytes uploads leaves every committed file with its blob" do
    scope = scope_fixture()

    # Fila vencida para o CID dos bytes compartilhados: os bytes ficam no
    # disco sem nenhuma referencia, exatamente o pasto do GC.
    file = upload_and_purge(scope, "iguais")
    backdate_enqueue(file.blob_cid, hours_ago(2))

    # Varios uploads dos MESMOS bytes (mesmo CID) correm com a rodada do GC:
    # sem a travessa (`Taina.Ybira.BlobLock`), o GC confere referencias entre
    # a gravacao dos bytes e o commit deles, apaga o blob e o arquivo
    # commita apontando para bytes que sairam do disco.
    gc_task = Task.async(fn -> Ybira.gc_blobs(hours_ago(1)) end)

    upload_tasks =
      for i <- 1..8 do
        Task.async(fn -> Ybira.upload(scope, tmp_upload_fixture("iguais", "corrida-#{i}.txt")) end)
      end

    assert {:ok, %{deleted: _, kept: _}} = Task.await(gc_task, 15_000)

    # Cada upload commita (a cota da Tekoa comporta os 9): a afirmacao do
    # teste e que NENHUM fica com a referencia para um blob fora do disco.
    files = Enum.map(Task.await_many(upload_tasks, 15_000), fn {:ok, file} -> file end)

    assert files |> Enum.map(& &1.blob_cid) |> Enum.uniq() |> length() == 1
    assert files |> Enum.map(& &1.blob_cid) |> Enum.uniq() == [file.blob_cid]

    for file <- files do
      assert {:ok, path} = Ybira.blob_path(file)
      assert File.exists?(path)
    end

    # A rodada tambem derruba a fila: referencia viva (kept) ou bytes
    # apagados (deleted), a fila cai dos dois jeitos.
    refute queue_row?(file.blob_cid)
  end

  # Sobe um arquivo, manda para a lixeira, envelhece o apagado_em alem do
  # cutoff de 30 dias e roda o expurgo: a fila do GC fica com o CID.
  defp upload_and_purge(scope, contents) do
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture(contents, "#{contents}.txt"))
    {:ok, _} = Ybira.delete_file(scope, file.rkey)

    backdate_apagado_em(file.id, days_ago(31))

    {:ok, 1} = Ybira.purge_deleted_files(days_ago(30))

    file
  end

  defp days_ago(n), do: DateTime.shift(DateTime.utc_now(), second: -n * @seconds_per_day)
  defp hours_ago(n), do: DateTime.shift(DateTime.utc_now(), second: -n * @seconds_per_hour)

  defp backdate_apagado_em(id, apagado_em) do
    Repo.update_all(
      from(f in YbiraFile, where: f.id == ^id),
      [set: [apagado_em: apagado_em]],
      skip_tekoa_id: true
    )
  end

  defp backdate_enqueue(blob_cid, enqueued_at) do
    Repo.update_all(
      from(q in Queue, where: q.blob_cid == ^blob_cid),
      [set: [enqueued_at: enqueued_at]],
      skip_tekoa_id: true
    )
  end

  defp queue_row?(blob_cid) do
    Repo.exists?(from(q in Queue, where: q.blob_cid == ^blob_cid), skip_tekoa_id: true)
  end

  defp blob_on_disk?(file) do
    case Ybira.blob_path(file) do
      {:ok, path} -> File.exists?(path)
      {:error, :not_found} -> false
    end
  end
end
