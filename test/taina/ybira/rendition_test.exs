defmodule Taina.Ybira.Workers.RenditionTest do
  use Taina.DataCase, async: true

  import ExUnit.CaptureIO
  import Taina.Fixtures

  alias Taina.Ybira
  alias Taina.Ybira.Workers.Rendition

  @moduletag capture_log: true

  # Oban roda `:inline` em teste, então o job de rendition acontece durante o
  # `upload/2`, daí podermos reler o arquivo logo em seguida. Os metadados de
  # rendição moram na tabela do produto (`Taina.Jaci.Photo`).

  defp metadata!(scope, file) do
    {:ok, metadata} = Ybira.photo_metadata(scope, file)
    metadata
  end

  test "image upload fills dimensions, EXIF slot and thumbnail paths" do
    scope = scope_fixture()

    {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "p.jpg"))
    {:ok, photo} = Ybira.get_file(scope, photo.rkey)
    metadata = metadata!(scope, photo)

    assert metadata["width"] == 50
    assert metadata["height"] == 40
    # imagem gerada não tem EXIF -> taken_at fica nulo (fallback é o upload)
    assert Map.has_key?(metadata, "taken_at")
    assert is_nil(metadata["taken_at"])
    assert %{"sm" => sm, "md" => md} = metadata["thumbnails"]
    assert File.exists?(sm)
    assert File.exists?(md)

    # sem EXIF, a dica de ordem do kernel também fica nula (o fallback da
    # linha do tempo é o instante do upload)
    {:ok, photo} = Ybira.get_file(scope, photo.rkey)
    assert is_nil(photo.effective_at)
  end

  test "non-image upload gets no renditions" do
    scope = scope_fixture()

    {:ok, doc} = Ybira.upload(scope, tmp_upload_fixture("texto", "a.txt"))
    {:ok, doc} = Ybira.get_file(scope, doc.rkey)

    refute Map.has_key?(metadata!(scope, doc), "thumbnails")
  end

  describe "render_file/2" do
    setup do
      %{scope: scope_fixture()}
    end

    test "regera a thumbnail que sumiu do disco", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "r.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.rkey)
      %{"sm" => sm, "md" => md} = metadata!(scope, photo)["thumbnails"]

      File.rm!(sm)
      File.rm!(md)

      assert :ok = Rendition.render_file(photo.id, scope.tekoa.public_id)
      assert File.exists?(sm)
      assert File.exists?(md)
    end

    test "arquivo apagado volta {:error, :gone}", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "g.jpg"))

      {:ok, _} = Ybira.delete_file(scope, photo.rkey)

      assert {:error, :gone} = Rendition.render_file(photo.id, scope.tekoa.public_id)
    end

    test "arquivo corrompido volta {:error, _} sem derrubar", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "c.jpg"))

      # bytes destruídos por baixo: o processamento falha, o registro fica
      {:ok, path} = Ybira.blob_path(photo)
      File.write!(path, "não é imagem nenhuma")

      assert {:error, _reason} = Rendition.render_file(photo.id, scope.tekoa.public_id)
    end

    test "falha grava rendition_error e deixa de ter thumbnails", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "e.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.rkey)
      assert match?(%{"sm" => _, "md" => _}, metadata!(scope, photo)["thumbnails"])

      # bytes destruídos por baixo: a falha fica registrada na foto, não só
      # no log, e a linha deixa de apontar thumbnails
      {:ok, path} = Ybira.blob_path(photo)
      File.write!(path, "não é imagem nenhuma")

      assert {:error, _reason} = Rendition.render_file(photo.id, scope.tekoa.public_id)

      metadata = metadata!(scope, photo)
      assert is_binary(metadata["rendition_error"]) and metadata["rendition_error"] != ""
      refute Map.has_key?(metadata, "thumbnails")
    end

    test "sucesso posterior substitui os metadados e limpa o rendition_error", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "l.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.rkey)

      {:ok, path} = Ybira.blob_path(photo)
      good = File.read!(path)
      File.write!(path, "não é imagem nenhuma")

      assert {:error, _reason} = Rendition.render_file(photo.id, scope.tekoa.public_id)
      assert metadata!(scope, photo)["rendition_error"]

      # bytes de volta: a rodada seguinte grava metadados novos, sem o erro
      File.write!(path, good)

      assert :ok = Rendition.render_file(photo.id, scope.tekoa.public_id)

      metadata = metadata!(scope, photo)
      refute Map.has_key?(metadata, "rendition_error")
      assert match?(%{"sm" => _, "md" => _}, metadata["thumbnails"])
    end
  end

  describe "set_effective_at/2" do
    # A imagem gerada pelo fixture nao tem EXIF, e a libvips re-encoda (e
    # perde) um EXIF feito a mao: o ramo com captura sai direto na funcao,
    # publicada `@doc false` para isso (o mesmo padrao de
    # `Media.extract_taken_at/1`).

    setup do
      %{scope: scope_fixture()}
    end

    test "grava a captura do EXIF como a dica de ordem do kernel", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(filename: "ea.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.rkey)

      assert :ok = Rendition.set_effective_at(photo, ~N[2024-01-01 10:00:00])

      {:ok, photo} = Ybira.get_file(scope, photo.rkey)
      # O EXIF nao carrega fuso: o cast do Ecto trata como UTC.
      assert photo.effective_at == ~U[2024-01-01 10:00:00Z]
    end

    test "sem EXIF nao toca o campo", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(filename: "en.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.rkey)

      assert :ok = Rendition.set_effective_at(photo, nil)

      {:ok, photo} = Ybira.get_file(scope, photo.rkey)
      assert is_nil(photo.effective_at)
    end
  end

  describe "mix taina.thumbnails.regenerate" do
    setup do
      %{scope: scope_fixture()}
    end

    test "regera as miniaturas de uma tekoa, com resumo", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "t.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.rkey)
      %{"sm" => sm, "md" => md} = metadata!(scope, photo)["thumbnails"]

      File.rm!(sm)
      File.rm!(md)

      # A tarefa escreve o resumo no terminal (`Mix.shell().info`); capturamos
      # para o `mix test` não virar eco da tarefa. `rerun`: a tarefa pode já
      # ter corrido neste VM (outro teste), e `run` não a invoca de novo.
      # `--tekoa=<id>`: o public_id pode começar com "-" e o OptionParser
      # o tomaria por opção.
      capture_io(fn ->
        Mix.Task.rerun("taina.thumbnails.regenerate", ["--tekoa=#{scope.tekoa.public_id}"])
      end)

      assert File.exists?(sm)
      assert File.exists?(md)
    end

    test "regerar em cima de uma falha limpa o rendition_error", %{scope: scope} do
      {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(width: 50, height: 40, filename: "f.jpg"))
      {:ok, photo} = Ybira.get_file(scope, photo.rkey)

      {:ok, path} = Ybira.blob_path(photo)
      good = File.read!(path)
      File.write!(path, "não é imagem nenhuma")

      assert {:error, _reason} = Rendition.render_file(photo.id, scope.tekoa.public_id)
      assert metadata!(scope, photo)["rendition_error"]

      File.write!(path, good)

      # A tarefa reusa o caminho do worker: sucesso substitui os metadados e
      # limpa o erro, do mesmo jeito que na fila.
      capture_io(fn ->
        Mix.Task.rerun("taina.thumbnails.regenerate", ["--tekoa=#{scope.tekoa.public_id}"])
      end)

      metadata = metadata!(scope, photo)
      refute Map.has_key?(metadata, "rendition_error")
      assert match?(%{"sm" => _, "md" => _}, metadata["thumbnails"])
    end
  end
end
