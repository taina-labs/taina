defmodule TainaWeb.LoginLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  @login_error "Não conseguimos entrar."

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

    assert html =~ "Entre com seu nome na nuvem da sua comunidade."
    assert html =~ "É com ele que você entra."
    assert has_element?(lv, ".auth-title", "Tainá")
    assert has_element?(lv, "button.auth-link", "Esqueci minha senha")
    assert has_element?(lv, ~s(form[action="/login"]))
    assert has_element?(lv, ~s(input[name="username"]))
    assert has_element?(lv, ~s(input[name="password"]))
  end

  test "sem o aviso de tamanho de senha no login (spec 6.5)", %{conn: conn} do
    tekoa_fixture()

    {:ok, _lv, html} = live(conn, ~p"/login")

    refute html =~ "Mínimo 8"
  end

  test "login que falhou acende o erro do campo da senha (board erro)", %{conn: conn} do
    tekoa_fixture()

    {:ok, lv, html} =
      conn
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> put_flash(:error, @login_error)
      |> live(~p"/login")

    # O flash do controller segue na casca e o board repete o aviso no campo;
    # o board `erro` não repete o subtítulo.
    assert html =~ @login_error
    assert html =~ "Confira a senha e tente de novo."
    assert has_element?(lv, ~s(.field--invalid input[name="password"]))
    refute html =~ "Entre com seu nome na nuvem da sua comunidade."
  end

  test "outro erro que cai no login (convite vencido) não acende o campo", %{conn: conn} do
    tekoa_fixture()

    expired = "Este convite expirou ou já foi usado. Peça um novo link a quem te convidou."

    {:ok, _lv, html} =
      conn
      |> init_test_session(%{})
      |> Phoenix.Controller.fetch_flash([])
      |> put_flash(:error, expired)
      |> live(~p"/login")

    assert html =~ expired
    refute html =~ "Confira a senha e tente de novo."
  end

  test "Esqueci minha senha abre a explicação da recuperação mediada", %{conn: conn} do
    tekoa_fixture()

    {:ok, lv, _html} = live(conn, ~p"/login")

    html = lv |> element("button", "Esqueci minha senha") |> render_click()

    assert html =~ "O Tainá não usa e-mail."
  end

  test "Tenho um convite leva ao /convite", %{conn: conn} do
    tekoa_fixture()

    {:ok, lv, _html} = live(conn, ~p"/login")

    assert {:error, {:live_redirect, %{to: "/convite"}}} =
             lv |> element("a", "Tenho um convite") |> render_click()
  end
end
