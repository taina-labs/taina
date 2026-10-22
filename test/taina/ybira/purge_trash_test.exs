defmodule Taina.Ybira.Workers.PurgeTrashTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira
  alias Taina.Ybira.Workers.PurgeTrash
  alias Ypy.Maraca.Tekoa
  alias Ypy.Ybira.File, as: YbiraFile
  alias Ypy.Ybira.Folder

  @seconds_per_day 86_400

  test "purges files trashed before the 30-day cutoff and reclaims their quota" do
    scope = scope_fixture()
    {:ok, old} = Ybira.upload(scope, tmp_upload_fixture("antigo", "old.txt"))
    {:ok, recent} = Ybira.upload(scope, tmp_upload_fixture("recente", "new.txt"))

    {:ok, _} = Ybira.delete_file(scope, old.rkey)
    {:ok, _} = Ybira.delete_file(scope, recent.rkey)

    backdate(YbiraFile, old.id, days_ago(31))
    backdate(YbiraFile, recent.id, days_ago(5))

    assert :ok = PurgeTrash.perform(%Oban.Job{args: %{}})

    refute blob_on_disk?(old)
    assert blob_on_disk?(recent)
    refute Repo.get(YbiraFile, old.id, skip_tekoa_id: true)
    assert Repo.get(YbiraFile, recent.id, skip_tekoa_id: true)

    tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
    assert tekoa.storage_used_bytes == recent.tamanho
  end

  test "purges a batch of expired files across owners and reclaims the summed quota" do
    scope = scope_fixture()
    other = ava_fixture(scope.tekoa)
    other_scope = Scope.new(other, scope.tekoa)

    {:ok, a} = Ybira.upload(scope, tmp_upload_fixture("aaa", "a.txt"))
    {:ok, b} = Ybira.upload(other_scope, tmp_upload_fixture("bbbbb", "b.txt"))
    {:ok, c} = Ybira.upload(scope, tmp_upload_fixture("cccccc", "c.txt"))
    {:ok, keep} = Ybira.upload(scope, tmp_upload_fixture("ddddddd", "keep.txt"))

    {:ok, _} = Ybira.delete_file(scope, a.rkey)
    {:ok, _} = Ybira.delete_file(other_scope, b.rkey)
    {:ok, _} = Ybira.delete_file(scope, c.rkey)
    {:ok, _} = Ybira.delete_file(scope, keep.rkey)

    backdate(YbiraFile, a.id, days_ago(31))
    backdate(YbiraFile, b.id, days_ago(40))
    backdate(YbiraFile, c.id, days_ago(31))
    backdate(YbiraFile, keep.id, days_ago(5))

    assert :ok = PurgeTrash.perform(%Oban.Job{args: %{}})

    refute blob_on_disk?(a)
    refute blob_on_disk?(b)
    refute blob_on_disk?(c)
    assert blob_on_disk?(keep)
    assert Repo.get(YbiraFile, keep.id, skip_tekoa_id: true)

    tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
    assert tekoa.storage_used_bytes == keep.tamanho
  end

  test "same bytes uploaded twice share the blob; purging one keeps the other's bytes" do
    scope = scope_fixture()
    {:ok, a} = Ybira.upload(scope, tmp_upload_fixture("iguais", "a.txt"))
    {:ok, b} = Ybira.upload(scope, tmp_upload_fixture("iguais", "b.txt"))

    # Endereçado por conteúdo: os mesmos bytes, mesmo CID, mesmo caminho.
    assert a.blob_cid == b.blob_cid

    {:ok, _} = Ybira.delete_file(scope, a.rkey)
    backdate(YbiraFile, a.id, days_ago(31))

    assert :ok = PurgeTrash.perform(%Oban.Job{args: %{}})

    refute Repo.get(YbiraFile, a.id, skip_tekoa_id: true)
    assert Repo.get(YbiraFile, b.id, skip_tekoa_id: true)
    assert blob_on_disk?(b)
  end

  test "purges every row sharing a blob: with no remaining reference the bytes go too" do
    scope = scope_fixture()
    {:ok, a} = Ybira.upload(scope, tmp_upload_fixture("iguais", "a.txt"))
    {:ok, b} = Ybira.upload(scope, tmp_upload_fixture("iguais", "b.txt"))

    assert a.blob_cid == b.blob_cid

    {:ok, _} = Ybira.delete_file(scope, a.rkey)
    {:ok, _} = Ybira.delete_file(scope, b.rkey)
    backdate(YbiraFile, a.id, days_ago(31))
    backdate(YbiraFile, b.id, days_ago(31))

    assert :ok = PurgeTrash.perform(%Oban.Job{args: %{}})

    # Nenhuma linha sobrando referenciando o CID: os bytes saem do disco.
    refute Repo.get(YbiraFile, a.id, skip_tekoa_id: true)
    refute Repo.get(YbiraFile, b.id, skip_tekoa_id: true)
    refute blob_on_disk?(a)
  end

  test "purges folders trashed before the cutoff, keeps the recent ones" do
    scope = scope_fixture()
    {:ok, old} = Ybira.create_folder(scope, %{name: "antiga"})
    {:ok, recent} = Ybira.create_folder(scope, %{name: "recente"})

    {:ok, :deleted} = Ybira.delete_folder(scope, old.rkey)
    {:ok, :deleted} = Ybira.delete_folder(scope, recent.rkey)

    backdate(Folder, old.id, days_ago(31))
    backdate(Folder, recent.id, days_ago(5))

    assert :ok = PurgeTrash.perform(%Oban.Job{args: %{}})

    refute Repo.get(Folder, old.id, skip_tekoa_id: true)
    assert Repo.get(Folder, recent.id, skip_tekoa_id: true)
  end

  defp days_ago(n), do: DateTime.shift(DateTime.utc_now(), second: -n * @seconds_per_day)

  defp backdate(schema, id, apagado_em) do
    Repo.update_all(
      from(r in schema, where: r.id == ^id),
      [set: [apagado_em: apagado_em]],
      skip_tekoa_id: true
    )
  end

  defp blob_on_disk?(file) do
    case Ybira.blob_path(file) do
      {:ok, path} -> File.exists?(path)
      {:error, :not_found} -> false
    end
  end
end
