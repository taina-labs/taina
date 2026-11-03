defmodule TainaWeb.UploadLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    %{scope: Scope.new(ava, tekoa), ava: ava, tekoa: tekoa}
  end

  # --- boards "Enviar / enviando" e o fluxo concluído ---

  test "envia arquivo e mostra no grupo concluído", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")

    input =
      file_input(lv, "#dropzone", :files, [
        %{name: "ata.txt", content: "ata da assembleia", type: "text/plain"}
      ])

    render_upload(input, "ata.txt")

    html = render(lv)
    assert html =~ "Concluído"
    assert html =~ "ata.txt"

    assert {:ok, %{items: [file]}} = Ybira.list_files(scope)
    assert file.nome == "ata.txt"
  end

  test "a tela publica os limites da fila de upload", %{conn: conn, ava: ava} do
    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")

    assert html =~ ~s(phx-hook="UploadQueue")
    assert html =~ ~s(data-upload-concurrency="10")
    assert html =~ ~s(data-upload-max-size="2147483648")

    html = render_hook(lv, "upload-rejected", %{"name" => "grande.bin", "reason" => "too_large"})

    assert html =~ "Falharam"
    assert html =~ "grande.bin"
  end

  test "o voltar aponta a pasta de destino, pelo nome", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})

    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar?#{[pasta: folder.rkey]}")

    assert has_element?(lv, ".page-header__title", "Documentos")
    assert has_element?(lv, ".page-header__back-label", "Atas")
    assert has_element?(lv, ~s(.page-header__back[href="/documentos/pasta/#{folder.rkey}"]))
  end

  test "return_to interno mantém a origem de Grade e Linha do tempo", %{conn: conn, ava: ava} do
    for origin <- ["/galeria?zona=casa", "/galeria/linha-do-tempo?zona=praca"] do
      path = "/documentos/enviar?return_to=" <> URI.encode_www_form(origin)
      {:ok, lv, _html} = conn |> log_in(ava) |> live(path)

      assert has_element?(lv, ~s(.page-header__back[href="#{origin}"]))
    end
  end

  test "return_to externo usa o fallback Casa", %{conn: conn, ava: ava} do
    path = "/documentos/enviar?return_to=" <> URI.encode_www_form("https://example.com/fora")
    {:ok, lv, _html} = conn |> log_in(ava) |> live(path)

    assert has_element?(lv, ~s(.page-header__back[href="/documentos"]))
    refute render(lv) =~ "example.com"
  end

  test "envia para a pasta indicada em ?pasta=", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar?#{[pasta: folder.rkey]}")

    input =
      file_input(lv, "#dropzone", :files, [
        %{name: "junho.txt", content: "ata de junho", type: "text/plain"}
      ])

    render_upload(input, "junho.txt")

    assert {:ok, %{files: [file]}} = Ybira.list_folder_contents(scope, folder.rkey)
    assert file.nome == "junho.txt"
  end

  test "arquivo rejeitado pelo Ybira aparece como falha", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")

    # ELF magic bytes, executável, rejeitado pela allowlist de MIME
    input =
      file_input(lv, "#dropzone", :files, [
        %{name: "virus.bin", content: <<0x7F, ?E, ?L, ?F, 0, 1, 2, 3>>, type: "application/octet-stream"}
      ])

    render_upload(input, "virus.bin")

    html = render(lv)
    assert html =~ "Falharam"
    assert html =~ "Não aceitamos este tipo de arquivo. Use imagens, PDFs, texto, áudio, vídeo ou ZIP."

    # rejeição vale no domínio, não só na UI: nada foi persistido
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
  end

  test "entrada da câmera chega a CONCLUÍDO", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")

    # JPEG de verdade: o Ybira detecta MIME pelos magic bytes, não pela extensão
    content = File.read!(tmp_image_fixture(width: 8, height: 8))

    input = file_input(lv, "#camera-input", :camera, [%{name: "foto-da-roca.jpg", content: content, type: "image/jpeg"}])
    render_upload(input, "foto-da-roca.jpg")

    html = render(lv)
    assert html =~ "Concluído"
    assert html =~ "foto-da-roca.jpg"

    assert {:ok, %{items: [file]}} = Ybira.list_files(scope)
    assert file.nome == "foto-da-roca.jpg"
  end

  test "a linha concluída mostra sucesso sem ação de publicar", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")

    input = file_input(lv, "#dropzone", :files, [%{name: "ata.txt", content: "ata da assembleia", type: "text/plain"}])
    render_upload(input, "ata.txt")

    html = render(lv)
    assert has_element?(lv, ".list-row .text-success")
    refute html =~ "Publicar na praça"
    refute html =~ "Na praça"
    refute html =~ "Você pode continuar usando o app enquanto envia."

    assert {:ok, %{items: [file]}} = Ybira.list_files(scope)
    assert file.zona == :casa
  end

  # --- board "Enviar / erro cota" ---

  test "erro de cota: a caixa explica com a cópia do board e aponta o espaço", %{
    conn: conn,
    scope: scope,
    ava: ava,
    tekoa: tekoa
  } do
    # cota de 10 bytes já consumida: qualquer envio estoura
    tekoa |> Ecto.Changeset.change(storage_quota_bytes: 10, storage_used_bytes: 10) |> Repo.update!()

    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/enviar")

    input =
      file_input(lv, "#dropzone", :files, [
        %{name: "grande.txt", content: "esse conteúdo passa da cota", type: "text/plain"}
      ])

    render_upload(input, "grande.txt")

    html = render(lv)
    assert has_element?(lv, ".dropzone--error-cota")
    assert html =~ "O espaço da comunidade acabou. Peça a quem cuida da nuvem para liberar."
    assert has_element?(lv, ~s(a[href="/armazenamento"]), "Ver espaço")
    # nada persistiu: a cota vale no domínio
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
  end
end
