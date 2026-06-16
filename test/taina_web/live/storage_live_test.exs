defmodule TainaWeb.StorageLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  setup do
    tekoa = tekoa_fixture()
    %{tekoa: tekoa, admin: zelador_fixture(tekoa), member: active_ava_fixture(tekoa)}
  end

  test "mostra uso e legenda por tipo", %{conn: conn, member: member} do
    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/armazenamento")

    assert html =~ "Uso por tipo"
    assert html =~ "Fotos"
    assert html =~ "Documentos"
    # membro comum não edita cota
    refute html =~ "Cota da comunidade"
  end

  test "admin atualiza a cota da comunidade", %{conn: conn, admin: admin} do
    {:ok, lv, html} = conn |> log_in(admin) |> live(~p"/armazenamento")

    assert html =~ "Cota da comunidade"

    lv |> element("button[phx-click=toggle-quota-modal]") |> render_click()
    lv |> form("#quota-modal form") |> render_submit(%{"quota" => %{"gigabytes" => "10"}})

    assert render(lv) =~ "10 GB"
  end
end
