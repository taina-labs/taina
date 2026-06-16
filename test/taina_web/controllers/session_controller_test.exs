defmodule TainaWeb.SessionControllerTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  @password "frase-longa-que-so-eu-lembro"

  describe "com instância inicializada" do
    setup do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa, %{username: "maria", password: @password})
      %{tekoa: tekoa, ava: ava}
    end

    test "login por nome de usuário cria sessão e vai para a home", %{conn: conn, ava: ava} do
      conn = post(conn, ~p"/login", %{"username" => ava.username, "password" => @password})

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :ava_id) == ava.public_id
    end

    test "senha errada volta para o login com aviso", %{conn: conn, ava: ava} do
      conn = post(conn, ~p"/login", %{"username" => ava.username, "password" => "senha-errada-123"})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "incorretos"
      refute get_session(conn, :ava_id)
    end

    test "logout derruba a sessão", %{conn: conn, ava: ava} do
      conn =
        conn
        |> log_in(ava)
        |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :ava_id)
    end
  end

  test "login sem comunidade ainda criada redireciona para o setup", %{conn: conn} do
    conn = post(conn, ~p"/login", %{"username" => "ninguem", "password" => @password})

    assert redirected_to(conn) == ~p"/setup"
    refute get_session(conn, :ava_id)
  end
end
