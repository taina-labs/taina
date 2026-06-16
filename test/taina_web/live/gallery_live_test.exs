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

    assert html =~ "/files/#{first.public_id}/thumbnail/sm"
    assert html =~ "/files/#{second.public_id}/thumbnail/sm"
  end

  test "linha do tempo agrupa por dia", %{conn: conn, ava: ava} do
    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/fotos/linha-do-tempo")

    assert html =~ "Hoje"
    assert html =~ "2 fotos"
  end

  test "visualizador navega entre fotos", %{conn: conn, ava: ava, first: first, second: second} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/fotos")

    # abre a mais recente (segunda) a partir da grade
    html = lv |> element(~s(a[href="/fotos/#{second.public_id}"])) |> render_click()
    assert html =~ "1 de 2"
    assert html =~ "segunda.jpg"

    # próxima = mais antiga
    lv |> element("button.viewer__nav--next") |> render_click()
    assert_patch(lv, ~p"/fotos/#{first.public_id}")
    assert render(lv) =~ "primeira.jpg"

    # fechar volta para a grade
    lv |> element("button[phx-click=close]") |> render_click()
    assert_patch(lv, ~p"/fotos")
  end

  test "excluir manda a foto para a lixeira e volta para a grade", %{conn: conn, ava: ava, scope: scope, second: second} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/fotos/#{second.public_id}")

    lv |> element("button[phx-click=ask-delete]") |> render_click()
    lv |> element("button[phx-click=confirm-delete]") |> render_click()
    assert_patch(lv, ~p"/fotos")

    assert {:error, :not_found} = Ybira.get_file(scope, second.public_id)
  end
end
