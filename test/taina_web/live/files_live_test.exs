defmodule TainaWeb.FilesLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    ava = confirmed_ava_fixture(tekoa)
    %{scope: Scope.new(ava, tekoa), ava: ava}
  end

  test "lista pastas e arquivos da raiz", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Documentos"})
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"))

    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos")

    assert html =~ folder.name
    assert html =~ file.original_filename
    assert html =~ "2 itens"
  end

  test "navega para dentro de uma pasta", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Fotos da comunidade"})

    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos/pasta/#{folder.public_id}")

    assert html =~ "Fotos da comunidade"
    assert html =~ "Pasta vazia"
  end

  test "cria pasta pelo modal", %{conn: conn, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos")

    lv |> element("button[phx-value-modal=new-folder]") |> render_click()
    lv |> form("#new-folder-modal form") |> render_submit(%{"folder" => %{"name" => "Vídeos"}})

    assert render(lv) =~ "Vídeos"
  end

  test "renomeia pasta", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Rascunho"})
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos")

    lv
    |> element(~s(button[phx-click*="open-rename"][phx-click*="#{folder.public_id}"]))
    |> render_click()

    lv |> form("#rename-modal form") |> render_submit(%{"folder" => %{"name" => "Definitivo"}})

    html = render(lv)
    assert html =~ "Definitivo"
    refute html =~ "Rascunho"
  end

  test "exclui arquivo para a lixeira", %{conn: conn, scope: scope, ava: ava} do
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "velho.txt"))
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos")

    lv
    |> element(~s(button[phx-click*="ask-delete"][phx-click*="#{file.public_id}"]))
    |> render_click()

    lv |> element(~s(button[phx-click="confirm-delete"])) |> render_click()

    refute render(lv) =~ "velho.txt"
    assert {:ok, %{items: [trashed]}} = Ybira.list_trash(scope)
    assert trashed.id == file.id
  end
end
