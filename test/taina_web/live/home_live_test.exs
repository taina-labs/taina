defmodule TainaWeb.HomeLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  test "sem sessão, redireciona para o login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  test "mostra comunidade, armazenamento e recentes", %{conn: conn} do
    tekoa = tekoa_fixture(%{name: "Quilombo do Café"})
    ava = confirmed_ava_fixture(tekoa)
    scope = Scope.new(ava, tekoa)
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "ata.txt"))

    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/")

    assert html =~ "Quilombo do Café"
    assert html =~ "Armazenamento"
    assert html =~ "Recentes"
    assert html =~ file.original_filename
  end
end
