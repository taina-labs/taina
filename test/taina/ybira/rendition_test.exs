defmodule Taina.Ybira.Workers.RenditionTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Ybira

  @moduletag capture_log: true

  # Oban roda `:inline` em teste, então o job de rendition acontece durante o
  # `upload/3` — daí podermos reler o arquivo logo em seguida.

  test "image upload fills dimensions, EXIF slot and thumbnail paths" do
    scope = scope_fixture()

    {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "p.jpg"))
    {:ok, photo} = Ybira.get_file(scope, photo.public_id)

    assert photo.metadata["width"] == 50
    assert photo.metadata["height"] == 40
    # imagem gerada não tem EXIF → taken_at fica nulo (fallback é o upload)
    assert Map.has_key?(photo.metadata, "taken_at")
    assert is_nil(photo.metadata["taken_at"])
    assert %{"sm" => sm, "md" => md} = photo.metadata["thumbnails"]
    assert File.exists?(sm)
    assert File.exists?(md)
  end

  test "non-image upload gets no renditions" do
    scope = scope_fixture()

    {:ok, doc} = Ybira.upload(scope, tmp_upload_fixture("texto", "a.txt"))
    {:ok, doc} = Ybira.get_file(scope, doc.public_id)

    refute Map.has_key?(doc.metadata, "thumbnails")
  end
end
