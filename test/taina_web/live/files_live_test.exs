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

    assert html =~ folder.nome
    assert html =~ file.nome
    assert html =~ "2 itens"
  end

  test "navega para dentro de uma pasta", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Fotos da comunidade"})

    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos/pasta/#{folder.rkey}")

    assert html =~ "Fotos da comunidade"
    # a pasta nova nasce na casa, e a listagem abre na casa por padrao
    assert html =~ "Sua casa está vazia"
  end

  describe "breadcrumb" do
    test "pasta aninhada mostra a cadeia de ancestrais completa", %{conn: conn, scope: scope, ava: ava} do
      {:ok, raiz} = Ybira.create_folder(scope, %{name: "Raiz"})
      {:ok, meio} = Ybira.create_folder(scope, %{name: "Meio", parent_rkey: raiz.rkey})
      {:ok, folha} = Ybira.create_folder(scope, %{name: "Folha", parent_rkey: meio.rkey})

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/arquivos/pasta/#{folha.rkey}")

      assert html =~ "Início"
      assert html =~ "Raiz"
      assert html =~ "Meio"
      assert html =~ "Folha"

      # cada ancestral é um link para a pasta dele
      assert has_element?(lv, ~s(a[href="/arquivos/pasta/#{raiz.rkey}"]), "Raiz")
      assert has_element?(lv, ~s(a[href="/arquivos/pasta/#{meio.rkey}"]), "Meio")
      # com meio na cadeia, o marcador de truncamento entra (visível no mobile)
      assert has_element?(lv, ~s(.breadcrumb .hide-desktop), "...")
      # a pasta atual fica sem link
      refute has_element?(lv, ~s(a[href="/arquivos/pasta/#{folha.rkey}"]))
    end

    test "pasta de primeiro nível não tem meio a truncar", %{conn: conn, scope: scope, ava: ava} do
      {:ok, raiz} = Ybira.create_folder(scope, %{name: "Raiz"})
      {:ok, folha} = Ybira.create_folder(scope, %{name: "Folha", parent_rkey: raiz.rkey})

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/arquivos/pasta/#{folha.rkey}")

      assert html =~ "Raiz"
      assert html =~ "Folha"
      assert has_element?(lv, ~s(a[href="/arquivos/pasta/#{raiz.rkey}"]), "Raiz")
      # sem meio, o marcador de truncamento não entra
      refute has_element?(lv, ~s(.breadcrumb .hide-desktop), "...")
    end
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
    |> element(~s(button[phx-click*="open-rename"][phx-click*="#{folder.rkey}"]))
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
    |> element(~s(button[phx-click*="ask-delete"][phx-click*="#{file.rkey}"]))
    |> render_click()

    lv |> element(~s(button[phx-click="confirm-delete"])) |> render_click()

    refute render(lv) =~ "velho.txt"
    assert {:ok, %{items: [trashed]}} = Ybira.list_trash(scope)
    assert trashed.id == file.id
  end

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  describe "zonas casa/praca" do
    test "casa e a aba padrao: mostra item da casa, esconde praca", %{conn: conn, scope: scope, ava: ava} do
      {:ok, casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "minha-casa.txt"))
      {:ok, praca} = Ybira.upload(scope, tmp_upload_fixture("oi", "na-praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, praca.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/arquivos")

      assert html =~ casa.original_filename
      refute html =~ praca.original_filename
      # aba Casa ativa sem ?zona= na URL; a praca pede o parametro explicito
      assert has_element?(lv, ~s(.segmented__option[aria-current="page"]), "Casa")
      assert has_element?(lv, ~s|.segmented__option:not([aria-current])|, "Praça")
      # linha de leitura curta da casa + acao oposta no menu do dono
      assert html =~ "Só você"
      assert html =~ "Publicar na praça"
    end

    test "?zona=praca mostra itens da praca, esconde os da casa", %{conn: conn, scope: scope, ava: ava} do
      {:ok, casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "minha-casa.txt"))
      {:ok, praca} = Ybira.upload(scope, tmp_upload_fixture("oi", "na-praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, praca.rkey)

      {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=praca")

      assert html =~ praca.original_filename
      refute html =~ casa.original_filename
      # linha de leitura curta da praca + acao oposta no menu do dono
      assert html =~ "Todos veem"
      assert html =~ "Tirar da praça"
    end

    test "publicar um arquivo da casa: ask -> confirm move para a praca", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{file.rkey}"]))
      |> render_click()

      lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

      assert render(lv) =~ "Publicado na praça."
      assert {:ok, updated} = Ybira.get_file(scope, file.rkey)
      assert updated.zona == :praca

      # aparece na praca depois do refresh
      {:ok, _lv2, praca_html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=praca")
      assert praca_html =~ file.nome
    end

    test "tirar da praca: ask -> confirm volta para casa", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "comunicado.txt"))
      {:ok, _} = Ybira.publicar_file(scope, file.rkey)
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=praca")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{file.rkey}"]))
      |> render_click()

      lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

      assert render(lv) =~ "Tirado da praça."
      assert {:ok, updated} = Ybira.get_file(scope, file.rkey)
      assert updated.zona == :casa

      refute render(lv) =~ file.nome
    end

    test "publicar uma pasta: confirm com aviso de nao-cascata", %{conn: conn, scope: scope, ava: ava} do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{folder.rkey}"]))
      |> render_click()

      html = render(lv)
      assert html =~ "Só a pasta entra na praça. Os arquivos dentro dela continuam como estão."

      lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

      assert {:ok, moved} = Ybira.get_folder(scope, folder.rkey)
      assert moved.zona == :praca
    end

    test "item da praca de outra pessoa nao mostra controle de zona", %{conn: conn, scope: scope, ava: ava} do
      outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
      outro_scope = Scope.new(outra, scope.tekoa)
      {:ok, file} = Ybira.upload(outro_scope, tmp_upload_fixture("oi", "da-outra.txt"))
      {:ok, _} = Ybira.publicar_file(outro_scope, file.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=praca")

      assert html =~ file.nome
      refute has_element?(lv, ~s(button[phx-click*="ask-zona"][phx-click*="#{file.rkey}"]))
    end

    test "praca vazia mostra o estado vazio da praca", %{conn: conn, scope: scope, ava: ava} do
      {:ok, _casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "so-casa.txt"))

      {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=praca")

      assert html =~ "A praça está vazia"
    end

    test "pasta na casa de outro morador volta ao início com o aviso", %{conn: conn, scope: scope, ava: ava} do
      outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
      {:ok, folder} = Ybira.create_folder(Scope.new(outra, scope.tekoa), %{name: "Rascunhos"})

      assert {:error, {_kind, %{to: to}}} =
               conn |> log_in(ava) |> live(~p"/arquivos/pasta/#{folder.rkey}")

      assert to == "/arquivos"
    end

    test "erro ao publicar mostra flash e nao quebra", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "doc.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos?zona=casa")

      lv
      |> element(~s(button[phx-click*="ask-zona"][phx-click*="#{file.rkey}"]))
      |> render_click()

      # remove o arquivo por baixo dos panos: publicar_file devolve {:error, :not_found}
      {:ok, _} = Ybira.delete_file(scope, file.rkey)

      assert render_click(element(lv, ~s(button[phx-click="confirm-zona"]))) =~ "Não foi possível publicar na praça."
    end
  end
end
