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

  # --- boards "Praca / padrao" (M, Web movel, Web 768) e "Casa / padrao" ---

  describe "zonas como abas" do
    test "a rota da praça lista só a praça, com a contagem e o remetente", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      outra = active_ava_fixture(scope.tekoa, %{username: "joao", display_name: "João"})
      {:ok, casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "minha-casa.txt"))
      {:ok, meu} = Ybira.upload(scope, tmp_upload_fixture("oi", "meu-na-praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, meu.rkey)
      {:ok, dela} = Ybira.upload(Scope.new(outra, scope.tekoa), tmp_upload_fixture("oi", "dela.txt"))
      {:ok, _} = Ybira.publicar_file(Scope.new(outra, scope.tekoa), dela.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos")

      assert html =~ "2 itens na praça"
      assert html =~ meu.nome
      assert html =~ "enviado por você"
      assert html =~ dela.nome
      assert html =~ "enviado por João"
      refute html =~ casa.nome

      # a zona é a aba: Praça acesa, sem seletor de zona na tela
      assert has_element?(lv, ~s(.service-tab-bar__item[aria-current="page"]), "Praça")
      refute has_element?(lv, ".segmented")
      # sem badge de zona por linha (a aba inteira já é a zona)
      refute html =~ "Todos veem"
    end

    test "a rota da casa lista só a casa, com a linha de ensino do board", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "minha-casa.txt"))
      {:ok, praca} = Ybira.upload(scope, tmp_upload_fixture("oi", "na-praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, praca.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      assert html =~ casa.nome
      refute html =~ praca.nome
      assert html =~ "Só você vê o que está na casa."
      assert html =~ "só você"
      assert has_element?(lv, ~s(.service-tab-bar__item[aria-current="page"]), "Casa")
    end

    test "a zona da raiz é filtrada antes da paginação", %{scope: scope} do
      {:ok, public_file} = Ybira.upload(scope, tmp_upload_fixture("oi", "na-praca.txt"))
      {:ok, _} = Ybira.publicar_file(scope, public_file.rkey)
      {:ok, _private_file} = Ybira.upload(scope, tmp_upload_fixture("oi", "na-casa.txt"))

      assert {:ok, %{files: [listed], next_cursor: nil}} =
               Ybira.list_folder_contents(scope, nil, zona: :praca, limit: 1)

      assert listed.rkey == public_file.rkey
    end
  end

  # --- board "Praca / pasta" (M e Web) ---

  describe "pasta" do
    test "mostra o título da pasta com a contagem de arquivos e o dia", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
      {:ok, _} = Ybira.upload(scope, tmp_upload_fixture("oi", "marco.txt"), folder_rkey: folder.rkey)
      {:ok, _} = Ybira.upload(scope, tmp_upload_fixture("oi", "abril.txt"), folder_rkey: folder.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/pasta/#{folder.rkey}")

      assert html =~ "2 arquivos"
      assert html =~ "atualizados hoje"
      assert has_element?(lv, ~s(.service-tab-bar__item[aria-current="page"]), "Casa")
      # pasta de primeiro nível: o voltar aponta a raiz da zona, palavra padrão
      assert has_element?(lv, ".service-header__back-label", "Início")
    end

    test "a linha da pasta diz quantos itens ela tem (board: Pasta, 4 itens)", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
      {:ok, _} = Ybira.upload(scope, tmp_upload_fixture("oi", "marco.txt"), folder_rkey: folder.rkey)
      {:ok, _} = Ybira.upload(scope, tmp_upload_fixture("oi", "abril.txt"), folder_rkey: folder.rkey)

      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      assert has_element?(lv, ".list-row--folder", "Atas")
      assert has_element?(lv, ".list-row--folder .list-row__meta", "Pasta, 2 itens")
    end

    test "pasta aninhada: o voltar aponta o parente pelo nome e a migalha nasce na zona", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, raiz} = Ybira.create_folder(scope, %{name: "Raiz"})
      {:ok, folha} = Ybira.create_folder(scope, %{name: "Folha", parent_rkey: raiz.rkey})

      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/pasta/#{folha.rkey}")

      assert has_element?(lv, ".service-header__back-label", "Raiz")

      # desktop: migalha enraizada na zona ("Casa > Raiz > Folha")
      assert has_element?(lv, ~s(.breadcrumb a[href="/documentos/casa"]), "Casa")
      assert has_element?(lv, ~s(.breadcrumb a[href="/documentos/pasta/#{raiz.rkey}"]), "Raiz")
      assert has_element?(lv, ".breadcrumb .breadcrumb__current", "Folha")

      assert {:error, {:live_redirect, %{to: to}}} =
               lv |> element(".service-header__back") |> render_click()

      assert to == "/documentos/pasta/#{raiz.rkey}"
    end

    test "pasta da praça abre na aba praça, com o conteúdo dela", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Comunitárias"})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "cartaz.txt"), folder_rkey: folder.rkey)
      {:ok, _} = Ybira.publicar_folder(scope, folder.rkey)
      {:ok, _} = Ybira.publicar_file(scope, file.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/pasta/#{folder.rkey}")

      assert html =~ file.nome
      assert has_element?(lv, ~s(.service-tab-bar__item[aria-current="page"]), "Praça")
      refute html =~ "A pasta nasce na sua casa"
    end

    test "arquivo publicado continua visível dentro da pasta da casa", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Documentos"})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"), folder_rkey: folder.rkey)

      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/pasta/#{folder.rkey}")

      lv
      |> element(~s(button[phx-click*="zona"][phx-click*="#{file.rkey}"]))
      |> render_click()

      assert render(lv) =~ "Publicado na praça."
      assert render(lv) =~ file.nome
      assert {:ok, updated} = Ybira.get_file(scope, file.rkey)
      assert updated.zona == :praca
    end

    test "publicar uma pasta publica os itens dela após confirmação", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
      other_scope = Scope.new(outra, scope.tekoa)
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Comunitárias"})
      {:ok, child} = Ybira.create_folder(scope, %{name: "Atas", parent_rkey: folder.rkey})
      {:ok, top_file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"), folder_rkey: folder.rkey)
      {:ok, child_file} = Ybira.upload(scope, tmp_upload_fixture("oi", "ata.txt"), folder_rkey: child.rkey)

      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      lv
      |> element(~s(button[phx-click*="zona"][phx-click*="#{folder.rkey}"]))
      |> render_click()

      assert has_element?(lv, "#confirm-remove", "Publicar pasta e conteúdo na praça?")
      lv |> element("#confirm-remove button", "Publicar tudo") |> render_click()

      assert render(lv) =~ "Publicado na praça."
      assert {:ok, public_folder} = Ybira.get_folder(other_scope, folder.rkey)
      assert public_folder.zona == :praca

      assert {:ok, %{folders: [public_child], files: [public_file]}} =
               Ybira.list_folder_contents(other_scope, folder.rkey)

      assert public_child.zona == :praca
      assert public_file.rkey == top_file.rkey
      assert {:ok, %{files: [public_child_file]}} = Ybira.list_folder_contents(other_scope, child.rkey)
      assert public_child_file.rkey == child_file.rkey
      assert public_child_file.zona == :praca
    end

    test "pasta na casa de outro morador volta ao início com o aviso", %{conn: conn, scope: scope, ava: ava} do
      outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
      {:ok, folder} = Ybira.create_folder(Scope.new(outra, scope.tekoa), %{name: "Rascunhos"})

      assert {:error, {_kind, %{to: to}}} =
               conn |> log_in(ava) |> live(~p"/documentos/pasta/#{folder.rkey}")

      assert to == "/documentos/casa"
    end
  end

  # --- boards "Praca / vazio" e "Casa / vazio" ---

  describe "estados vazios" do
    test "a praça vazia não tem botão de enviar (publicar é um ato explícito)", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, _casa} = Ybira.upload(scope, tmp_upload_fixture("oi", "so-casa.txt"))

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos")

      assert html =~ "A praça está vazia"
      assert html =~ "Quando alguém publicar um arquivo na praça, ele aparece aqui para toda a comunidade."
      refute has_element?(lv, "a", "Enviar um arquivo")
    end

    test "a casa vazia oferece o envio como ação primária", %{conn: conn, ava: ava} do
      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      assert html =~ "Sua casa está vazia"
      assert html =~ "Envie um arquivo. Ele fica só com você até você publicar na praça."
      assert has_element?(lv, "a", "Enviar um arquivo")
    end
  end

  # --- boards "Overlay / Sheet acoes" e "Overlay / Dialog remover" ---

  describe "ações de linha" do
    test "o menu da casa oferece Abrir, Baixar, Publicar na praça, Mover, Renomear e Remover", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      for label <- ["Abrir", "Baixar", "Publicar na praça", "Mover", "Renomear", "Remover"] do
        assert has_element?(lv, ~s(#item-file-#{file.rkey}-panel), label)
      end

      assert has_element?(lv, ~s(#item-file-#{file.rkey}), "Ações do arquivo")
    end

    test "o menu da praça troca a ação de zona: Voltar para a casa, não Publicar", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "comunicado.txt"))
      {:ok, _} = Ybira.publicar_file(scope, file.rkey)
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos")

      assert has_element?(lv, ~s(#item-file-#{file.rkey}-panel), "Voltar para a casa")
      refute has_element?(lv, ~s(#item-file-#{file.rkey}-panel), "Publicar na praça")
    end

    test "item alheio só oferece Abrir e Baixar: o servidor recusa o resto", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
      {:ok, file} = Ybira.upload(Scope.new(outra, scope.tekoa), tmp_upload_fixture("oi", "da-outra.txt"))
      {:ok, _} = Ybira.publicar_file(Scope.new(outra, scope.tekoa), file.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos")

      assert html =~ file.nome
      assert has_element?(lv, ~s(#item-file-#{file.rkey}-panel), "Abrir")
      assert has_element?(lv, ~s(#item-file-#{file.rkey}-panel), "Baixar")

      for label <- ["Publicar na praça", "Mover", "Renomear", "Remover"] do
        refute has_element?(lv, ~s(#item-file-#{file.rkey}-panel), label)
      end
    end

    test "publicar do menu move o arquivo para a praça", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      lv
      |> element(~s(button[phx-click*="zona"][phx-click*="#{file.rkey}"]))
      |> render_click()

      assert render(lv) =~ "Publicado na praça."
      assert {:ok, updated} = Ybira.get_file(scope, file.rkey)
      assert updated.zona == :praca

      {:ok, _lv, praca_html} = conn |> log_in(ava) |> live(~p"/documentos")
      assert praca_html =~ file.nome
    end

    test "tirar da praça devolve o arquivo para a casa", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "comunicado.txt"))
      {:ok, _} = Ybira.publicar_file(scope, file.rkey)
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos")

      lv
      |> element(~s(button[phx-click*="zona"][phx-click*="#{file.rkey}"]))
      |> render_click()

      assert render(lv) =~ "Tirado da praça."
      assert {:ok, updated} = Ybira.get_file(scope, file.rkey)
      assert updated.zona == :casa
    end

    test "erro ao publicar mostra flash e não quebra", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "doc.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      # remove o arquivo por baixo dos panos: publicar_file devolve {:error, :not_found}
      {:ok, _} = Ybira.delete_file(scope, file.rkey)

      assert render_click(element(lv, ~s(button[phx-click*="zona"][phx-click*="#{file.rkey}"]))) =~
               "Não foi possível publicar na praça."
    end

    test "Remover abre o diálogo destrutivo e manda para a lixeira", %{
      conn: conn,
      scope: scope,
      ava: ava
    } do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "velho.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      lv
      |> element(~s(button[phx-click*="ask-delete"][phx-click*="#{file.rkey}"]))
      |> render_click()

      # diálogo destrutivo do board: título com o nome e a cópia dos 30 dias
      assert has_element?(lv, ~s(#confirm-remove.dialog .dialog__title), "Remover velho.txt?")

      assert has_element?(
               lv,
               ~s(#confirm-remove .dialog__body),
               "O arquivo vai para a lixeira e some de vez depois de 30 dias."
             )

      lv |> element(~s(#confirm-remove button[phx-click="confirm-delete"])) |> render_click()

      refute render(lv) =~ "velho.txt"
      assert {:ok, %{items: [trashed]}} = Ybira.list_trash(scope)
      assert trashed.id == file.id
    end
  end

  # --- fluxos de domínio preservados ---

  describe "fluxos preservados" do
    test "cria pasta pelo modal", %{conn: conn, ava: ava} do
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      lv |> element("button[phx-value-modal=new-folder]") |> render_click()
      lv |> form("#new-folder-modal form") |> render_submit(%{"folder" => %{"name" => "Vídeos"}})

      assert render(lv) =~ "Vídeos"
    end

    test "renomeia arquivo pelo menu", %{conn: conn, scope: scope, ava: ava} do
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "rascunho.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      lv
      |> element(~s(button[phx-click*="open-rename"][phx-click*="#{file.rkey}"]))
      |> render_click()

      lv |> form("#rename-modal form") |> render_submit(%{"folder" => %{"name" => "definitivo.txt"}})

      html = render(lv)
      assert html =~ "definitivo.txt"
      refute html =~ "rascunho.txt"
    end

    test "move arquivo pelo seletor de pastas", %{conn: conn, scope: scope, ava: ava} do
      {:ok, destino} = Ybira.create_folder(scope, %{name: "Destino"})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "solto.txt"))
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/casa")

      lv
      |> element(~s(button[phx-click*="open-move"][phx-click*="#{file.rkey}"]))
      |> render_click()

      lv
      |> element(~s(button[phx-click*="move-item"][phx-click*="#{destino.rkey}"]))
      |> render_click()

      assert render(lv) =~ "Movido."
      assert {:ok, %{files: [movido]}} = Ybira.list_folder_contents(scope, destino.rkey)
      assert movido.id == file.id
    end
  end
end
