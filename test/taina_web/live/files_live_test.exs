defmodule TainaWeb.FilesLiveTest do
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

  test "lista pastas e arquivos da raiz", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Documentos"})
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"))

    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

    assert html =~ folder.name
    assert html =~ file.original_filename
    assert html =~ "2 itens"
  end

  test "navega para dentro de uma pasta", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Fotos da comunidade"})

    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos/pasta/#{folder.public_id}")

    assert html =~ "Fotos da comunidade"
    assert html =~ "A praça está vazia"
  end

  test "cria pasta pelo modal", %{conn: conn, ava: ava} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

    lv |> element("button[phx-value-modal=new-folder]") |> render_click()
    lv |> form("#new-folder-modal form") |> render_submit(%{"folder" => %{"name" => "Vídeos"}})

    assert render(lv) =~ "Vídeos"
  end

  test "renomeia pasta", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Rascunho"})
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

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
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

    lv
    |> element(~s(button[phx-click*="ask-delete"][phx-click*="#{file.public_id}"]))
    |> render_click()

    lv |> element(~s(button[phx-click="confirm-delete"])) |> render_click()

    refute render(lv) =~ "velho.txt"
    assert {:ok, %{items: [trashed]}} = Ybira.list_trash(scope)
    assert trashed.id == file.id
  end

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  describe "zonas casa/praca" do
    test "praca e a aba padrao: mostra item da praca, esconde casa", %{conn: conn, scope: scope, ava: ava} do
      {:ok, casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "minha-casa.txt"))
      {:ok, praca} = Ybira.upload(scope, tmp_upload_fixture("oi", "na-praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, praca.public_id)

      {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos")

      assert html =~ praca.original_filename
      refute html =~ casa.original_filename
      # aba Praca ativa por padrao
      assert html =~ ~s(aria-current="true")
      # linha de leitura da praca + acao oposta no menu
      assert html =~ "Todos os moradores veem."
      assert html =~ "Tirar da praça"
    end

    test "?zona=casa mostra meus itens da casa, esconde praca", %{conn: conn, scope: scope, ava: ava} do
      {:ok, casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "minha-casa.txt"))
      {:ok, praca} = Ybira.upload(scope, tmp_upload_fixture("oi", "na-praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, praca.public_id)

      {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

      assert html =~ casa.original_filename
      refute html =~ praca.original_filename
      # linha de leitura da casa + acao oposta no menu
      assert html =~ "Só você, e quem você deixar."
      assert html =~ "Publicar na praça"
    end

    test "publicar um arquivo da casa: ask -> confirm move para a praca", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{file.public_id}"]))
      |> render_click()

      lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

      assert render(lv) =~ "Publicado na praça."
      assert {:ok, updated} = Ybira.get_file(scope, file.public_id)
      assert updated.zona == :praca

      # aparece na praca depois do refresh
      {:ok, _lv2, praca_html} = conn |> log_in(ava) |> live(~p"/arquivos")
      assert praca_html =~ file.original_filename
    end

    test "tirar da praca: ask -> confirm volta para casa", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "comunicado.txt"))
      {:ok, _} = Ybira.publicar_file(scope, file.public_id)
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{file.public_id}"]))
      |> render_click()

      lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

      assert render(lv) =~ "Tirado da praça."
      assert {:ok, updated} = Ybira.get_file(scope, file.public_id)
      assert updated.zona == :casa

      refute render(lv) =~ file.original_filename
    end

    test "publicar uma pasta: confirm com aviso de nao-cascata", %{conn: conn, scope: scope, ava: ava} do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{folder.public_id}"]))
      |> render_click()

      html = render(lv)
      assert html =~ "Só a pasta entra na praça. Os arquivos dentro dela continuam como estão."

      lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

      assert {:ok, moved} = Ybira.get_folder(scope, folder.public_id)
      assert moved.zona == :praca
    end

    test "item da praca de outra pessoa nao mostra controle de zona", %{conn: conn, scope: scope, ava: ava} do
      outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
      outro_scope = Scope.new(outra, scope.tekoa)
      {:ok, file} = Ybira.upload(outro_scope, tmp_upload_fixture("oi", "da-outra.txt"))
      {:ok, _} = Ybira.publicar_file(outro_scope, file.public_id)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/arquivos")

      assert html =~ file.original_filename
      refute has_element?(lv, ~s(button[phx-click*="ask-zona"][phx-click*="#{file.public_id}"]))
    end

    test "praca vazia mostra o estado vazio da praca", %{conn: conn, scope: scope, ava: ava} do
      {:ok, _casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "so-casa.txt"))

      {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos")

      assert html =~ "A praça está vazia"
    end

    test "erro ao publicar mostra flash e nao quebra", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "doc.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{file.public_id}"]))
      |> render_click()

      # remove o arquivo por baixo dos panos: publicar_file devolve {:error, :not_found}
      {:ok, _} = Ybira.delete_file(scope, file.public_id)

      assert render_click(element(lv, ~s(button[phx-click="confirm-zona"]))) =~ "Não foi possível publicar na praça."
    end
  end
end
