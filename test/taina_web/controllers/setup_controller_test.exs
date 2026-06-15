defmodule TainaWeb.SetupControllerTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca

  @params %{
    "setup" => %{
      "community_name" => "Quilombo do Café",
      "username" => "Ana Oliveira",
      "email" => "ana@exemplo.org",
      "password" => "frase-longa-segura",
      "password_confirmation" => "frase-longa-segura"
    }
  }

  test "bootstrap cria a Tekoa + admin e já entra logado", %{conn: conn} do
    conn = post(conn, ~p"/setup", @params)

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :ava_id)
    assert Maraca.bootstrapped?()
    assert {:ok, tekoa} = Maraca.get_tekoa()
    assert tekoa.name == "Quilombo do Café"
  end

  test "instância já inicializada manda para o login", %{conn: conn} do
    tekoa_fixture()

    conn = post(conn, ~p"/setup", @params)
    assert redirected_to(conn) == ~p"/login"
  end

  test "dados inválidos voltam para o wizard com aviso", %{conn: conn} do
    params = put_in(@params, ["setup", "password"], "curta")
    conn = post(conn, ~p"/setup", params)

    assert redirected_to(conn) == ~p"/setup"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Revise"
    refute Maraca.bootstrapped?()
  end
end
