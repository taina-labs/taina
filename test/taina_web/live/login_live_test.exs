defmodule TainaWeb.LoginLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  test "instância virgem redireciona para o setup", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/setup"}}} = live(conn, ~p"/login")
  end

  test "quem já está logado vai direto para a home", %{conn: conn} do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)

    assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in(ava) |> live(~p"/login")
  end

  test "renderiza o form de login apontando para o POST /login", %{conn: conn} do
    tekoa_fixture()

    {:ok, lv, html} = live(conn, ~p"/login")

    assert html =~ "Boas-vindas de volta"
    assert has_element?(lv, ~s(form[action="/login"]))
    assert has_element?(lv, ~s(input[name="username"]))
    assert has_element?(lv, ~s(input[name="password"]))
  end

  test "o convite abre pelo código, sem link completo", %{conn: conn} do
    tekoa_fixture()

    {:ok, lv, _html} = live(conn, ~p"/login")

    # O campo do link não tem `field` nem `value`: é o caso que derrubava o
    # render com KeyError.
    assert lv |> element("button", "Tenho um convite") |> render_click() =~
             "Cole aqui o link do convite"

    assert {:error, {:live_redirect, %{to: "/convite/abc123"}}} =
             lv
             |> element("#invite-code-form")
             |> render_submit(%{"code" => " abc123 "})
  end
end
