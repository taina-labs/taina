defmodule TainaWeb.SetupControllerTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca

  @gb 1024 * 1024 * 1024

  @params %{
    "setup" => %{
      "community_name" => "Quilombo do Café",
      "username" => "ana",
      "display_name" => "Ana Oliveira",
      "password" => "frase-longa-segura",
      "storage_quota" => "inteiro"
    }
  }

  test "bootstrap cria a Tekoa + zelador e já entra logado, com o disco inteiro", %{conn: conn} do
    conn = post(conn, ~p"/setup", @params)

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :ava_id)
    assert Maraca.bootstrapped?()
    assert {:ok, tekoa} = Maraca.get_tekoa()
    assert tekoa.name == "Quilombo do Café"
    # "O disco inteiro" (spec 11.3): sem cota, o teto é o próprio disco.
    assert is_nil(tekoa.storage_quota_bytes)
  end

  test "um limite em GB vira bytes na cota", %{conn: conn} do
    params =
      @params
      |> put_in(["setup", "storage_quota"], "limite")
      |> put_in(["setup", "quota_gb"], "5")

    post(conn, ~p"/setup", params)

    assert {:ok, tekoa} = Maraca.get_tekoa()
    assert tekoa.storage_quota_bytes == 5 * @gb
  end

  test "um limite inválido (zero) volta ao passo 3 com o aviso do campo", %{conn: conn} do
    params =
      @params
      |> put_in(["setup", "storage_quota"], "limite")
      |> put_in(["setup", "quota_gb"], "0")

    conn = post(conn, ~p"/setup", params)

    assert redirected_to(conn) == ~p"/setup?passo=3"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "número de GB maior que zero"
    refute Maraca.bootstrapped?()
  end

  test "um limite maior que o disco volta ao passo 3 com o aviso do teto", %{conn: conn} do
    params =
      @params
      |> put_in(["setup", "storage_quota"], "limite")
      |> put_in(["setup", "quota_gb"], "999999999")

    conn = post(conn, ~p"/setup", params)

    assert redirected_to(conn) == ~p"/setup?passo=3"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Escolha um limite menor"
    refute Maraca.bootstrapped?()
  end

  test "sem a escolha de limite, o POST volta ao passo 3 sem criar nada", %{conn: conn} do
    params = Map.delete(@params["setup"], "storage_quota")

    conn = post(conn, ~p"/setup", %{"setup" => params})

    assert redirected_to(conn) == ~p"/setup?passo=3"
    refute Maraca.bootstrapped?()
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
