defmodule TainaWeb.LiveDashboardTest do
  @moduledoc """
  Painel do zelador (RFC_003 seção 6, camada 3): o portão é o papel, não o
  ambiente de build. Morador e visitante veem 404, como se não existisse.
  """

  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  setup do
    tekoa = tekoa_fixture()
    %{zelador: zelador_fixture(tekoa), morador: active_ava_fixture(tekoa)}
  end

  test "zelador entra no painel", %{conn: conn, zelador: zelador} do
    conn = conn |> log_in(zelador) |> get(~p"/painel-do-zelador")

    # O dashboard normaliza a raiz para a página "home".
    assert {302, [to]} = {conn.status, Plug.Conn.get_resp_header(conn, "location")}
    assert to == "/painel-do-zelador/home"

    conn = get(conn, to)
    assert conn.status == 200
  end

  test "morador vê 404", %{conn: conn, morador: morador} do
    conn = conn |> log_in(morador) |> get(~p"/painel-do-zelador")

    assert conn.status == 404
  end

  test "visitante vê 404", %{conn: conn} do
    conn = get(conn, ~p"/painel-do-zelador")

    assert conn.status == 404
  end
end
