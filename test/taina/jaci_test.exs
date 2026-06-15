defmodule Taina.JaciTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Jaci
  alias Taina.Ybira
  alias Taina.Ybira.File, as: YbiraFile

  @moduletag capture_log: true

  describe "list_photos/2" do
    test "returns only images, newest upload first" do
      scope = scope_fixture()
      {:ok, _doc} = Ybira.upload(scope, tmp_upload_fixture("texto", "a.txt"))
      {:ok, p1} = Ybira.upload(scope, tmp_image_fixture(filename: "1.jpg"))
      {:ok, p2} = Ybira.upload(scope, tmp_image_fixture(filename: "2.jpg"))

      {:ok, %{items: items, next_cursor: nil}} = Jaci.list_photos(scope)
      assert Enum.map(items, & &1.public_id) == [p2.public_id, p1.public_id]
    end

    test "paginates by opaque cursor" do
      scope = scope_fixture()
      for i <- 1..3, do: {:ok, _} = Ybira.upload(scope, tmp_image_fixture(filename: "#{i}.jpg"))

      {:ok, %{items: first, next_cursor: cursor}} = Jaci.list_photos(scope, limit: 2)
      assert length(first) == 2
      assert is_binary(cursor)

      {:ok, %{items: rest, next_cursor: nil}} = Jaci.list_photos(scope, limit: 2, after_cursor: cursor)
      assert length(rest) == 1
    end
  end

  describe "timeline/2" do
    test "orders by EXIF capture date, not upload date" do
      scope = scope_fixture()
      {:ok, other} = Ybira.upload(scope, tmp_image_fixture(filename: "o.jpg"))
      {:ok, recent} = Ybira.upload(scope, tmp_image_fixture(filename: "r.jpg"))

      # enviada por último, mas tirada há anos -> deve ir para o fim da timeline,
      # contrariando a ordem de upload (senão o teste passa mesmo ignorando EXIF)
      set_taken_at(recent.id, ~N[2024-01-01 10:00:00])

      {:ok, %{groups: groups}} = Jaci.timeline(scope)
      ordered = groups |> Enum.flat_map(& &1.photos) |> Enum.map(& &1.public_id)
      assert ordered == [other.public_id, recent.public_id]
    end

    test "groups photos by effective date" do
      scope = scope_fixture()
      {:ok, a} = Ybira.upload(scope, tmp_image_fixture(filename: "a.jpg"))
      {:ok, b} = Ybira.upload(scope, tmp_image_fixture(filename: "b.jpg"))

      set_taken_at(a.id, ~N[2023-07-15 09:00:00])
      set_taken_at(b.id, ~N[2023-07-15 18:00:00])

      {:ok, %{groups: groups}} = Jaci.timeline(scope)
      assert [%{date: ~D[2023-07-15], photos: photos}] = groups
      assert length(photos) == 2
    end
  end

  # Sobrescreve o metadata para simular EXIF (a imagem gerada não tem). Operação
  # de sistema -> `skip_tekoa_id`.
  defp set_taken_at(file_id, %NaiveDateTime{} = dt) do
    Repo.update_all(
      from(f in YbiraFile, where: f.id == ^file_id),
      [set: [metadata: %{"taken_at" => NaiveDateTime.to_iso8601(dt)}]],
      skip_tekoa_id: true
    )
  end
end
