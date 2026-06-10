defmodule Taina.Ybira.Workers.PurgeTrashTest do
  use Taina.DataCase, async: false

  import Taina.Fixtures

  alias Taina.Maraca.Tekoa
  alias Taina.Ybira
  alias Taina.Ybira.File, as: YbiraFile
  alias Taina.Ybira.Folder
  alias Taina.Ybira.Workers.PurgeTrash

  @seconds_per_day 86_400

  test "purges files trashed before the 30-day cutoff and reclaims their quota" do
    scope = scope_fixture()
    {:ok, old} = Ybira.upload(scope, tmp_upload_fixture("antigo", "old.txt"))
    {:ok, recent} = Ybira.upload(scope, tmp_upload_fixture("recente", "new.txt"))

    {:ok, _} = Ybira.delete_file(scope, old.public_id)
    {:ok, _} = Ybira.delete_file(scope, recent.public_id)

    backdate(YbiraFile, old.id, days_ago(31))
    backdate(YbiraFile, recent.id, days_ago(5))

    assert :ok = PurgeTrash.perform(%Oban.Job{args: %{}})

    refute File.exists?(old.filepath)
    assert File.exists?(recent.filepath)
    refute Repo.get(YbiraFile, old.id, skip_tekoa_id: true)
    assert Repo.get(YbiraFile, recent.id, skip_tekoa_id: true)

    tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
    assert tekoa.storage_used_bytes == recent.file_size_bytes
  end

  test "purges folders trashed before the cutoff, keeps the recent ones" do
    scope = scope_fixture()
    {:ok, old} = Ybira.create_folder(scope, %{name: "antiga"})
    {:ok, recent} = Ybira.create_folder(scope, %{name: "recente"})

    {:ok, :deleted} = Ybira.delete_folder(scope, old.public_id)
    {:ok, :deleted} = Ybira.delete_folder(scope, recent.public_id)

    backdate(Folder, old.id, days_ago(31))
    backdate(Folder, recent.id, days_ago(5))

    assert :ok = PurgeTrash.perform(%Oban.Job{args: %{}})

    refute Repo.get(Folder, old.id, skip_tekoa_id: true)
    assert Repo.get(Folder, recent.id, skip_tekoa_id: true)
  end

  defp days_ago(n), do: DateTime.add(DateTime.utc_now(), -n * @seconds_per_day, :second)

  defp backdate(schema, id, deleted_at) do
    Repo.update_all(
      from(r in schema, where: r.id == ^id),
      [set: [deleted_at: deleted_at]],
      skip_tekoa_id: true
    )
  end
end
