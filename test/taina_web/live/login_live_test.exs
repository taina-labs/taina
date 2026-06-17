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

    assert html =~ "Bem-vindo de volta"
    assert has_element?(lv, ~s(form[action="/login"]))
    assert has_element?(lv, ~s(input[name="username"]))
    assert has_element?(lv, ~s(input[name="password"]))
  end
end
