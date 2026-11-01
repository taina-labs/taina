defmodule TainaWeb.FilePreviewLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa)
    other = active_ava_fixture(tekoa, %{username: "carla", display_name: "Carla"})
    {:ok, file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture("oi", "particular.txt"))
    %{tekoa: tekoa, owner: owner, other: other, target_file: file}
  end

  # --- board "Arquivo / casa alheia" ---

  test "casa alheia renders the board state, com o título genérico", %{
    conn: conn,
    other: other,
    target_file: file
  } do
    {:ok, lv, html} = conn |> log_in(other) |> live(~p"/documentos/#{file.rkey}")

    # o título não vaza o nome do arquivo para quem não pode lê lo
    assert has_element?(lv, ".page-header__title", "Documento")
    assert html =~ "Esta casa é particular"
    assert html =~ "Este arquivo está na casa de outra pessoa. Só quem guardou pode liberar."
    assert has_element?(lv, "button", "Pedir acesso")
  end

  test "pedir acesso cria o pedido e leva para os Pedidos", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, lv, _html} = conn |> log_in(other) |> live(~p"/documentos/#{file.rkey}")

    assert {:error, {:live_redirect, %{to: "/conta/pedidos"}}} =
             lv |> element("button", "Pedir acesso") |> render_click()

    assert {:ok, [request]} = Maraca.pedidos_recebidos(Scope.new(owner, tekoa))
    assert request.pedinte_id == other.id
    assert request.dono_id == owner.id
    assert request.recurso == file.rkey
    # sem campo na tela, o pedido vai sem motivo: o servidor nao fabrica frase
    assert request.motivo == nil
  end

  # --- board "Arquivo / padrao" (M e Web) ---

  test "o dono vê o título com o nome do arquivo, o badge de zona e os detalhes", %{
    conn: conn,
    owner: owner,
    target_file: file
  } do
    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

    assert has_element?(lv, ".page-header__title", file.nome)
    assert html =~ "Enviado por"
    assert html =~ "você"
    assert html =~ "Quando"
    assert html =~ "Hoje"
    assert html =~ "Onde"
    assert html =~ "Casa"
    assert has_element?(lv, ".badge--casa", "casa")
  end

  test "arquivo da praça: badge e o Onde dizem a zona, o voltar aponta a pasta", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner
  } do
    scope = Scope.new(owner, tekoa)
    {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "ata.txt"), folder_rkey: folder.rkey)
    {:ok, _} = Ybira.publicar_file(scope, file.rkey)

    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

    assert has_element?(lv, ".badge--praca", "praça")
    assert html =~ "Praça, pasta Atas"
    assert has_element?(lv, ~s(a[href="/documentos/pasta/#{folder.rkey}"]))
    assert has_element?(lv, ".page-header__back-label", "Atas")
  end

  test "as ações: Baixar no cabeçalho e no corpo, Remover só para o dono", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, _} = Ybira.publicar_file(Scope.new(owner, tekoa), file.rkey)

    {:ok, owner_lv, _html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

    assert has_element?(owner_lv, ~s(a[aria-label="Baixar"]))
    assert has_element?(owner_lv, "button", "Remover")
    # o menu do cabeçalho: Baixar, Voltar para a casa (o arquivo está na
    # praça), Remover
    assert has_element?(owner_lv, "#file-actions-panel", "Baixar")
    assert has_element?(owner_lv, "#file-actions-panel", "Voltar para a casa")
    refute has_element?(owner_lv, "#file-actions-panel", "Publicar na praça")
    assert has_element?(owner_lv, "#file-actions-panel", "Remover")

    {:ok, other_lv, _html} = conn |> log_in(other) |> live(~p"/documentos/#{file.rkey}")

    assert has_element?(other_lv, ~s(a[aria-label="Baixar"]))
    refute has_element?(other_lv, "button", "Remover")
    refute has_element?(other_lv, "#file-actions-panel", "Publicar na praça")
  end

  test "dono publica pelo menu do cabeçalho", %{conn: conn, tekoa: tekoa, owner: owner, target_file: file} do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

    lv |> element(~s(button[phx-click*="zona"])) |> render_click()

    assert render(lv) =~ "Publicado na praça."
    assert {:ok, updated} = Ybira.get_file(Scope.new(owner, tekoa), file.rkey)
    assert updated.zona == :praca
  end

  test "Remover abre o diálogo destrutivo e manda para a lixeira", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    target_file: file
  } do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

    lv |> element(~s(button[phx-click="ask-delete"])) |> render_click()

    assert has_element?(lv, ~s(#confirm-remove .dialog__title), "Remover particular.txt?")

    assert has_element?(
             lv,
             ~s(#confirm-remove .dialog__body),
             "O arquivo vai para a lixeira e some de vez depois de 30 dias."
           )

    # a tela navega de volta para a casa depois de remover
    assert {:error, {:live_redirect, %{to: "/documentos/casa"}}} =
             lv |> element(~s(#confirm-remove button[phx-click="confirm-delete"])) |> render_click()

    assert {:ok, %{items: [trashed]}} = Ybira.list_trash(Scope.new(owner, tekoa))
    assert trashed.id == file.id
  end

  test "a readable file renders the preview, not the ask-access state", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, _} = Ybira.publicar_file(Scope.new(owner, tekoa), file.rkey)

    {:ok, _view, html} = conn |> log_in(other) |> live(~p"/documentos/#{file.rkey}")

    refute html =~ "Pedir acesso"
  end

  describe "voltar para a pasta do arquivo" do
    test "arquivo dentro de pasta volta para a pasta, não para o início", %{
      conn: conn,
      tekoa: tekoa,
      owner: owner
    } do
      scope = Scope.new(owner, tekoa)
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Documentos"})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "dentro.txt"), folder_rkey: folder.rkey)

      {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

      assert html =~ ~s(href="/documentos/pasta/#{folder.rkey}")
    end

    test "arquivo solto na raiz volta para o início", %{conn: conn, owner: owner, target_file: file} do
      {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

      assert html =~ ~s(href="/documentos/casa")
      assert has_element?(lv, ".page-header__back-label", "Casa")
      refute html =~ "/documentos/pasta/"
    end

    test "arquivo solto na praça volta para a praça", %{
      conn: conn,
      tekoa: tekoa,
      owner: owner,
      target_file: file
    } do
      {:ok, _} = Ybira.publicar_file(Scope.new(owner, tekoa), file.rkey)

      {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/documentos/#{file.rkey}")

      assert html =~ ~s(href="/documentos")
      assert has_element?(lv, ".page-header__back-label", "Praça")
    end
  end
end
