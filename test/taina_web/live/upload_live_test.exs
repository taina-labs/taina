defmodule TainaWeb.UploadLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    %{scope: Scope.new(ava, tekoa), ava: ava}
  end

  test "envia arquivo e mostra no grupo concluído", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos/enviar")

    input =
      file_input(lv, "#dropzone", :files, [
        %{name: "ata.txt", content: "ata da assembleia", type: "text/plain"}
      ])

    render_upload(input, "ata.txt")

    html = render(lv)
    assert html =~ "Concluído"
    assert html =~ "ata.txt"

    assert {:ok, %{items: [file]}} = Ybira.list_files(scope)
    assert file.original_filename == "ata.txt"
  end

  test "envia para a pasta indicada em ?pasta=", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos/enviar?#{[pasta: folder.public_id]}")

    input =
      file_input(lv, "#dropzone", :files, [
        %{name: "junho.txt", content: "ata de junho", type: "text/plain"}
      ])

    render_upload(input, "junho.txt")

    assert {:ok, %{files: [file]}} = Ybira.list_folder_contents(scope, folder.public_id)
    assert file.original_filename == "junho.txt"
  end

  test "arquivo rejeitado pelo Ybira aparece como falha", %{conn: conn, scope: scope, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos/enviar")

    # ELF magic bytes, executável, rejeitado pela allowlist de MIME
    input =
      file_input(lv, "#dropzone", :files, [
        %{name: "virus.bin", content: <<0x7F, ?E, ?L, ?F, 0, 1, 2, 3>>, type: "application/octet-stream"}
      ])

    render_upload(input, "virus.bin")

    html = render(lv)
    assert html =~ "Falharam"
    assert html =~ "tipo de arquivo não permitido"

    # rejeição vale no domínio, não só na UI: nada foi persistido
    assert {:ok, %{items: []}} = Ybira.list_files(scope)
  end
end
