defmodule Taina.Ybira.RenditionStatusTest do
  use Taina.DataCase, async: true

  import Ecto.Query
  import Taina.Fixtures

  alias Taina.Jaci.Photo
  alias Taina.Repo
  alias Taina.Ybira
  alias Taina.Ybira.RenditionStatus
  alias Taina.Ybira.Workers.Rendition

  @moduletag capture_log: true

  # Oban roda `:inline` em teste: o job de rendition acontece durante o
  # `upload/2`, então o estado logo após o upload é `:ready` para imagens.

  test "arquivo que não é imagem deriva :none" do
    scope = scope_fixture()
    {:ok, doc} = Ybira.upload(scope, tmp_upload_fixture("texto", "a.txt"))
    {:ok, doc} = Ybira.get_file(scope, doc.rkey)

    assert RenditionStatus.status(scope, doc) == :none
  end

  test "imagem com miniaturas deriva :ready" do
    scope = scope_fixture()
    {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "r.jpg"))
    {:ok, photo} = Ybira.get_file(scope, photo.rkey)

    assert RenditionStatus.status(scope, photo) == :ready
  end

  test "imagem cuja rendição falhou deriva :unavailable" do
    scope = scope_fixture()
    {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "u.jpg"))
    {:ok, photo} = Ybira.get_file(scope, photo.rkey)

    {:ok, path} = Ybira.blob_path(photo)
    File.write!(path, "não é imagem nenhuma")

    assert {:error, _reason} = Rendition.render_file(photo.id, scope.tekoa.public_id)
    assert RenditionStatus.status(scope, photo) == :unavailable
  end

  test "imagem sem linha de foto deriva :pending" do
    scope = scope_fixture()
    {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "p.jpg"))
    {:ok, photo} = Ybira.get_file(scope, photo.rkey)

    drop_photo_row(photo.id, scope)

    assert RenditionStatus.status(scope, photo) == :pending
  end

  # A rendição ainda não rodou é o estado de quem perdeu a linha de foto
  # (ou de um job na fila); removemos a linha para reproduzi-lo.
  defp drop_photo_row(file_id, scope) do
    {:ok, _} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok, from(p in Photo, where: p.file_id == ^file_id) |> Repo.one() |> Repo.delete!()}
      end)
  end
end
