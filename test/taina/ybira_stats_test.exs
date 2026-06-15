defmodule Taina.YbiraStatsTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Ybira

  setup do
    %{scope: scope_fixture()}
  end

  describe "list_recent/2" do
    test "devolve os últimos envios, mais novos primeiro, fora da lixeira", %{scope: scope} do
      {:ok, old} = Ybira.upload(scope, tmp_upload_fixture("um", "a.txt"))
      {:ok, deleted} = Ybira.upload(scope, tmp_upload_fixture("dois", "b.txt"))
      {:ok, newest} = Ybira.upload(scope, tmp_upload_fixture("três", "c.txt"))
      {:ok, _} = Ybira.delete_file(scope, deleted.public_id)

      assert {:ok, [first, second]} = Ybira.list_recent(scope, limit: 2)
      assert first.id == newest.id
      assert second.id == old.id
    end
  end

  describe "count_files/1 e count_photos/1" do
    test "contam ativos; fotos só image/*", %{scope: scope} do
      {:ok, _doc} = Ybira.upload(scope, tmp_upload_fixture())
      {:ok, _img} = Ybira.upload(scope, tmp_image_fixture())
      {:ok, trashed} = Ybira.upload(scope, tmp_upload_fixture("x", "x.txt"))
      {:ok, _} = Ybira.delete_file(scope, trashed.public_id)

      assert {:ok, 2} = Ybira.count_files(scope)
      assert {:ok, 1} = Ybira.count_photos(scope)
    end
  end

  describe "storage_stats_by_kind/1" do
    test "agrupa bytes por categoria de mídia", %{scope: scope} do
      {:ok, doc} = Ybira.upload(scope, tmp_upload_fixture("documento", "doc.txt"))
      {:ok, img} = Ybira.upload(scope, tmp_image_fixture())

      assert {:ok, by_kind} = Ybira.storage_stats_by_kind(scope)
      assert by_kind.photos == img.file_size_bytes
      assert by_kind.documents == doc.file_size_bytes
      assert by_kind.videos == 0
      assert by_kind.others == 0
    end

    test "tudo zerado sem arquivos", %{scope: scope} do
      assert {:ok, %{photos: 0, videos: 0, documents: 0, others: 0}} = Ybira.storage_stats_by_kind(scope)
    end
  end
end
