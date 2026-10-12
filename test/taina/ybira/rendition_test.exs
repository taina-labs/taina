defmodule Taina.Ybira.Workers.RenditionTest do
  use Taina.DataCase, async: true

  import ExUnit.CaptureIO
  import Taina.Fixtures

  alias Taina.Ybira

  # Oban roda `:inline` em teste, então o job de rendition acontece durante o
  # `upload/3`, daí podermos reler o arquivo logo em seguida.

  alias Taina.Ybira.Workers.Rendition

  @moduletag capture_log: true

  test "image upload fills dimensions, EXIF slot and thumbnail paths" do
    scope = scope_fixture()

    {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "p.jpg"))
    {:ok, photo} = Ybira.get_file(scope, photo.public_id)

    assert photo.metadata["width"] == 50
    assert photo.metadata["height"] == 40
    # imagem gerada não tem EXIF -> taken_at fica nulo (fallback é o upload)
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

  describe "render_file/2" do
    setup do
      %{scope: scope_fixture()}
    end

    test "regera a thumbnail que sumiu do disco", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "r.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.public_id)
      %{"sm" => sm, "md" => md} = photo.metadata["thumbnails"]

      File.rm!(sm)
      File.rm!(md)

      assert :ok = Rendition.render_file(photo.id, scope.tekoa.public_id)
      assert File.exists?(sm)
      assert File.exists?(md)
    end

    test "arquivo apagado volta {:error, :gone}", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "g.jpg"))

      {:ok, _} = Ybira.delete_file(scope, photo.public_id)

      assert {:error, :gone} = Rendition.render_file(photo.id, scope.tekoa.public_id)
    end

    test "arquivo corrompido volta {:error, _} sem derrubar", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "c.jpg"))

      # bytes destruídos por baixo: o processamento falha, o registro fica
      File.write!(photo.filepath, "não é imagem nenhuma")

      assert {:error, _reason} = Rendition.render_file(photo.id, scope.tekoa.public_id)
    end
  end

  describe "mix taina.thumbnails.regenerate" do
    setup do
      %{scope: scope_fixture()}
    end

    test "regera as miniaturas de uma tekoa, com resumo", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "t.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.public_id)
      %{"sm" => sm, "md" => md} = photo.metadata["thumbnails"]

      File.rm!(sm)
      File.rm!(md)

      # A tarefa escreve o resumo no terminal (`Mix.shell().info`); capturamos
      # para o `mix test` não virar eco da tarefa.
      capture_io(fn ->
        Mix.Task.run("taina.thumbnails.regenerate", ["--tekoa", scope.tekoa.public_id])
      end)

      assert File.exists?(sm)
      assert File.exists?(md)
    end
  end
end
