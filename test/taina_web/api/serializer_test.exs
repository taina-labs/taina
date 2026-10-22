defmodule TainaWeb.API.SerializerTest do
  use TainaWeb.ConnCase, async: true

  import Ecto.Query
  import Taina.Fixtures

  alias Taina.Jaci.Photo
  alias Taina.Repo
  alias Taina.Scope
  alias TainaWeb.API.Serializer

  @moduletag capture_log: true

  setup do
    tekoa = tekoa_fixture()
    dono = active_ava_fixture(tekoa)
    %{scope: Scope.new(dono, tekoa)}
  end

  test "o lote devolve os MESMOS mapas do unitario", %{scope: scope} do
    {:ok, folder} = Taina.Ybira.create_folder(scope, %{name: "ferias"})
    {:ok, solto} = Taina.Ybira.upload(scope, tmp_upload_fixture("a", "solto.txt"))
    {:ok, guardado} = Taina.Ybira.upload(scope, tmp_upload_fixture("b", "guardado.txt"), folder_rkey: folder.rkey)
    {:ok, imagem} = Taina.Ybira.upload(scope, tmp_image_fixture(filename: "foto.jpg"))

    set_metadata(
      imagem.id,
      %{"thumbnails" => %{"sm" => "x.webp"}, "taken_at" => "2026-01-02T03:04:05"},
      ~U[2026-01-02 00:00:00Z]
    )

    files = [solto, guardado, imagem]

    assert Serializer.files(scope, files) == Enum.map(files, &Serializer.file(scope, &1))
  end

  test "o lote resolve o estado da rendition dos metadados que ja vieram", %{scope: scope} do
    {:ok, pendente} = Taina.Ybira.upload(scope, tmp_image_fixture(filename: "pendente.jpg"))
    {:ok, pronta} = Taina.Ybira.upload(scope, tmp_image_fixture(filename: "pronta.jpg"))

    # o worker roda junto do upload em teste: para ter um pendente, a linha
    # da foto sai (como no `drop_photo_row` do jaci_test)
    drop_photo_row(scope, pendente.id)

    set_metadata(pronta.id, %{"thumbnails" => %{"sm" => "x.webp"}}, ~U[2026-01-02 00:00:00Z])

    assert [%{"rendition" => "pending"}, %{"rendition" => "ready"}] =
             Serializer.files(scope, [pendente, pronta])
  end

  test "pagina vazia e lote vazio", %{scope: scope} do
    assert Serializer.files(scope, []) == []
  end

  test "o dono sai resolvido (public_id), em arquivo e pasta, do mesmo jeito no lote", %{
    scope: scope
  } do
    {:ok, folder} = Taina.Ybira.create_folder(scope, %{name: "ferias"})
    {:ok, file} = Taina.Ybira.upload(scope, tmp_upload_fixture("a", "a.txt"))

    assert Serializer.file(scope, file)["dono"] == scope.ava.public_id
    assert Serializer.folder(scope, folder)["dono"] == scope.ava.public_id

    # o lote devolve exatamente os mesmos mapas do unitario, dono inclusive
    assert Serializer.files(scope, [file]) == [Serializer.file(scope, file)]
    assert Serializer.folders(scope, [folder]) == [Serializer.folder(scope, folder)]
  end

  # A linha de foto pode ja existir (o worker roda no upload em teste):
  # upsert, com o `updated_at` sob controle do teste (o carimbo e o que o
  # ETag observa).
  defp set_metadata(file_id, metadata, updated_at) do
    %Photo{file_id: file_id}
    |> Photo.changeset(%{metadata: metadata})
    |> Repo.insert!(
      on_conflict: [set: [metadata: metadata, updated_at: updated_at]],
      conflict_target: :file_id,
      skip_tekoa_id: true
    )
  end

  defp drop_photo_row(scope, file_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      {:ok, from(p in Photo, where: p.file_id == ^file_id) |> Repo.one!() |> Repo.delete()}
    end)
  end
end
