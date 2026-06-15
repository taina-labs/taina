defmodule TainaWeb.MembersLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  setup do
    tekoa = tekoa_fixture()
    admin = admin_fixture(tekoa, %{username: "Ana Oliveira"})
    member = confirmed_ava_fixture(tekoa, %{username: "João Mendes"})
    %{tekoa: tekoa, admin: admin, member: member}
  end

  test "lista membros com papel e estado", %{conn: conn, admin: admin} do
    {:ok, _lv, html} = conn |> log_in(admin) |> live(~p"/membros")

    assert html =~ "Ana Oliveira"
    assert html =~ "João Mendes"
    assert html =~ "Administração, você"
    assert html =~ "2 pessoas"
  end

  test "busca filtra a lista", %{conn: conn, admin: admin} do
    {:ok, lv, _html} = conn |> log_in(admin) |> live(~p"/membros")

    html = lv |> element("form.search") |> render_change(%{"query" => "joão"})

    assert html =~ "João Mendes"
    refute html =~ "Ana Oliveira"
  end

  test "membro comum não vê atalho de convite", %{conn: conn, member: member} do
    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/membros")

    refute html =~ "/membros/convidar"
  end
end
