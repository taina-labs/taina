defmodule TainaWeb.GalleryLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    scope = Scope.new(ava, tekoa)

    {:ok, first} = Ybira.upload(scope, tmp_image_fixture(filename: "primeira.jpg"))
    {:ok, second} = Ybira.upload(scope, tmp_image_fixture(filename: "segunda.jpg"))

    %{scope: scope, ava: ava, first: first, second: second}
  end

  test "grade lista thumbnails das fotos", %{conn: conn, ava: ava, first: first, second: second} do
    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/fotos")

    assert html =~ "/files/#{first.rkey}/thumbnail/sm"
    assert html =~ "/files/#{second.rkey}/thumbnail/sm"
  end

  test "linha do tempo agrupa por dia", %{conn: conn, ava: ava} do
    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/fotos/linha-do-tempo")

    assert html =~ "Hoje"
    assert html =~ "2 fotos"
  end

  test "visualizador navega entre fotos", %{conn: conn, ava: ava, first: first, second: second} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/fotos")

    # abre a mais recente (segunda) a partir da grade
    html = lv |> element(~s(a[href="/fotos/#{second.rkey}"])) |> render_click()
    assert html =~ "1 de 2"
    assert html =~ "segunda.jpg"

    # próxima = mais antiga
    lv |> element("button.viewer__nav--next") |> render_click()
    assert_patch(lv, ~p"/fotos/#{first.rkey}")
    assert render(lv) =~ "primeira.jpg"

    # fechar volta para a grade
    lv |> element("button[phx-click=close]") |> render_click()
    assert_patch(lv, ~p"/fotos")
  end

  test "excluir manda a foto para a lixeira e volta para a grade", %{conn: conn, ava: ava, scope: scope, second: second} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/fotos/#{second.rkey}")

    lv |> element("button[phx-click=ask-delete]") |> render_click()
    lv |> element("button[phx-click=confirm-delete]") |> render_click()
    assert_patch(lv, ~p"/fotos")

    assert {:error, :not_found} = Ybira.get_file(scope, second.rkey)
  end

  test "foto na casa de outro morador leva para a tela de pedir acesso", %{conn: conn, ava: ava, scope: scope} do
    outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
    {:ok, file} = Ybira.upload(Scope.new(outra, scope.tekoa), tmp_image_fixture(filename: "particular.jpg"))

    assert {:error, {_kind, %{to: to}}} = conn |> log_in(ava) |> live(~p"/fotos/#{file.rkey}")
    assert to == "/arquivos/#{file.rkey}"
  end

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  describe "zonas casa/praca" do
    test "o padrao e Tudo: o conjunto legivel inteiro, com o badge da zona no tile", %{
      conn: conn,
      ava: ava,
      scope: scope,
      first: first
    } do
      {:ok, _} = Ybira.publicar_file(scope, first.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/fotos")

      # a publicada e a da casa, cada uma com a sua zona no tile
      assert html =~ "primeira.jpg"
      assert html =~ "segunda.jpg"
      assert has_element?(lv, ".photo-grid__tag", "Praça")
      assert has_element?(lv, ".photo-grid__tag", "Casa")
      assert has_element?(lv, ~s(.segmented__option[aria-current="page"]), "Tudo")
    end

    test "a aba casa mostra so o que esta na casa; a praca, so as publicadas", %{
      conn: conn,
      ava: ava,
      scope: scope,
      first: first
    } do
      {:ok, _} = Ybira.publicar_file(scope, first.rkey)

      {:ok, _lv, casa_html} = conn |> log_in(ava) |> live(~p"/fotos?zona=casa")

      refute casa_html =~ "primeira.jpg"
      assert casa_html =~ "segunda.jpg"

      {:ok, _lv, praca_html} = conn |> log_in(ava) |> live(~p"/fotos?zona=praca")

      assert praca_html =~ "primeira.jpg"
      refute praca_html =~ "segunda.jpg"
    end

    test "a linha do tempo acompanha o filtro da zona", %{conn: conn, ava: ava, scope: scope, first: first} do
      {:ok, _} = Ybira.publicar_file(scope, first.rkey)

      {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/fotos/linha-do-tempo?zona=praca")

      assert html =~ "primeira.jpg"
      refute html =~ "segunda.jpg"
    end

    test "os detalhes dizem a zona da foto", %{conn: conn, ava: ava, second: second} do
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/fotos/#{second.rkey}")

      lv |> element("button[phx-click=toggle-details]") |> render_click()

      html = render(lv)
      assert html =~ "Quem vê"
      assert html =~ "Na sua casa: só você, e quem você deixar."
    end

    test "publicar da tela do visualizador: ask -> confirm manda para a praca", %{
      conn: conn,
      ava: ava,
      scope: scope,
      second: second
    } do
      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/fotos/#{second.rkey}")

      html = render(lv)
      assert html =~ "Publicar na praça"

      lv |> element("button[phx-click=ask-zona]") |> render_click()
      lv |> element("button[phx-click=confirm-zona]") |> render_click()

      assert render(lv) =~ "Publicado na praça."
      assert {:ok, updated} = Ybira.get_file(scope, second.rkey)
      assert updated.zona == :praca

      # o visualizador espelha o estado novo, com a alavanca invertida
      assert render(lv) =~ "Tirar da praça"
    end

    test "quem não é dono não vê a alavanca de zona no visualizador", %{conn: conn, ava: ava, scope: scope} do
      outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
      outro_scope = Scope.new(outra, scope.tekoa)
      {:ok, file} = Ybira.upload(outro_scope, tmp_image_fixture(filename: "alheia.jpg"))
      {:ok, _} = Ybira.publicar_file(outro_scope, file.rkey)

      {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/fotos/#{file.rkey}")

      refute has_element?(lv, "button[phx-click=ask-zona]")
    end
  end
end
