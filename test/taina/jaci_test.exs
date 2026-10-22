defmodule Taina.JaciTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Jaci
  alias Taina.Jaci.Photo
  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  @moduletag capture_log: true

  describe "list_photos/2" do
    test "returns only images, newest upload first" do
      scope = scope_fixture()
      {:ok, _doc} = Ybira.upload(scope, tmp_upload_fixture("texto", "a.txt"))
      {:ok, p1} = Ybira.upload(scope, tmp_image_fixture(filename: "1.jpg"))
      {:ok, p2} = Ybira.upload(scope, tmp_image_fixture(filename: "2.jpg"))

      {:ok, %{items: items, next_cursor: nil}} = Jaci.list_photos(scope)
      assert Enum.map(items, & &1.rkey) == [p2.rkey, p1.rkey]
    end

    test "inclui vídeos e exclui tipos fora de image/video" do
      scope = scope_fixture()
      {:ok, _doc} = Ybira.upload(scope, tmp_upload_fixture("texto", "a.txt"))
      {:ok, img} = Ybira.upload(scope, tmp_image_fixture(filename: "foto.jpg"))
      {:ok, vid} = Ybira.upload(scope, tmp_video_fixture("clipe.mp4"))

      {:ok, %{items: items}} = Jaci.list_photos(scope)
      ids = Enum.map(items, & &1.rkey)
      assert img.rkey in ids
      assert vid.rkey in ids
      assert length(ids) == 2
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
      ordered = groups |> Enum.flat_map(& &1.photos) |> Enum.map(& &1.rkey)
      assert ordered == [other.rkey, recent.rkey]
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

    test "rajada no mesmo segundo nao pula fotos na paginacao" do
      scope = scope_fixture()

      photos =
        for i <- 1..4 do
          {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(filename: "r#{i}.jpg"))
          photo
        end

      # Mesmo instante para todos, nas DUAS codificacoes que a linha do tempo
      # encontra: metade pelo fallback do upload (a gravacao do Ecto, com Z)
      # e metade pelo EXIF simulado (a gravacao do worker, sem Z). As duas
      # formas do mesmo segundo nao podem virar chaves de keyset distintas,
      # senao a virada de pagina pula fotos.
      force_uploaded_at(scope, photos, DateTime.new!(~D[2024-06-01], ~T[10:00:00]))
      set_taken_at(Enum.at(photos, 2).id, ~N[2024-06-01 10:00:00])
      set_taken_at(Enum.at(photos, 3).id, ~N[2024-06-01 10:00:00])

      # As duas primeiras perdem a linha de foto: caem no fallback do upload.
      photos |> Enum.take(2) |> Enum.each(&drop_photo_row(&1.id, scope))

      collected = walk_timeline(scope, limit: 2)
      expected = photos |> Enum.reverse() |> Enum.map(& &1.rkey)

      assert Enum.map(collected, & &1.rkey) == expected
    end
  end

  # --- regra de leitura das duas zonas (kernel) ---

  describe "read rule across zones" do
    test "list_photos hides another resident's casa photo until it is published" do
      tekoa = tekoa_fixture()
      a = Scope.new(active_ava_fixture(tekoa), tekoa)
      b = Scope.new(active_ava_fixture(tekoa), tekoa)
      z = Scope.new(zelador_fixture(tekoa), tekoa)
      {:ok, photo} = Ybira.upload(a, tmp_image_fixture(filename: "p.jpg"))

      refute photo.rkey in photo_ids(Jaci.list_photos(b))
      refute photo.rkey in photo_ids(Jaci.list_photos(z))
      assert photo.rkey in photo_ids(Jaci.list_photos(a))

      {:ok, _} = Ybira.publicar_file(a, photo.rkey)

      assert photo.rkey in photo_ids(Jaci.list_photos(b))
      assert photo.rkey in photo_ids(Jaci.list_photos(z))
    end

    test "list_photos shows a casa photo to an Ava with an explicit concessao" do
      tekoa = tekoa_fixture()
      a = Scope.new(active_ava_fixture(tekoa), tekoa)
      b = Scope.new(active_ava_fixture(tekoa), tekoa)
      {:ok, photo} = Ybira.upload(a, tmp_image_fixture(filename: "p.jpg"))

      {:ok, _} = Maraca.conceder(a, "ypy.file.v0", photo.rkey, b.ava)

      assert photo.rkey in photo_ids(Jaci.list_photos(b))
    end

    test "timeline hides another resident's casa photo until it is published" do
      tekoa = tekoa_fixture()
      a = Scope.new(active_ava_fixture(tekoa), tekoa)
      b = Scope.new(active_ava_fixture(tekoa), tekoa)
      {:ok, photo} = Ybira.upload(a, tmp_image_fixture(filename: "p.jpg"))

      refute photo.rkey in timeline_ids(Jaci.timeline(b))
      assert photo.rkey in timeline_ids(Jaci.timeline(a))

      {:ok, _} = Ybira.publicar_file(a, photo.rkey)

      assert photo.rkey in timeline_ids(Jaci.timeline(b))
    end
  end

  defp photo_ids({:ok, %{items: items}}), do: Enum.map(items, & &1.rkey)

  defp timeline_ids({:ok, %{groups: groups}}) do
    Enum.flat_map(groups, fn %{photos: photos} -> Enum.map(photos, & &1.rkey) end)
  end

  # Grava o metadata de rendicao com o EXIF simulado (a imagem gerada nao tem).
  # Operacao de sistema -> `skip_tekoa_id`.
  defp set_taken_at(file_id, %NaiveDateTime{} = dt) do
    %Photo{file_id: file_id}
    |> Photo.changeset(%{metadata: %{"taken_at" => NaiveDateTime.to_iso8601(dt)}})
    |> Repo.insert!(
      on_conflict: [set: [metadata: %{"taken_at" => NaiveDateTime.to_iso8601(dt)}]],
      conflict_target: :file_id,
      skip_tekoa_id: true
    )
  end

  # Forca o `inserted_at` de todos os arquivos para o mesmo instante: sem
  # isso a rajada do teste depende do relogio da maquina.
  defp force_uploaded_at(scope, photos, %DateTime{} = instant) do
    {:ok, _} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        ids = Enum.map(photos, & &1.id)

        {:ok,
         Repo.update_all(
           from(f in Ypy.Ybira.File, where: f.id in ^ids),
           set: [inserted_at: instant]
         )}
      end)
  end

  defp drop_photo_row(file_id, scope) do
    {:ok, _} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok,
         from(p in Photo, where: p.file_id == ^file_id)
         |> Repo.one()
         |> Repo.delete!()}
      end)
  end

  defp walk_timeline(scope, opts, acc \\ []) do
    {:ok, %{groups: groups, next_cursor: next}} = Jaci.timeline(scope, opts)
    acc = acc ++ Enum.flat_map(groups, & &1.photos)

    if next,
      do: walk_timeline(scope, Keyword.put(opts, :after_cursor, next), acc),
      else: acc
  end
end
