defmodule TainaWeb.InviteDeepLinkTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  @moduletag capture_log: true

  test "zelador ve os dois QR: o link da web e o deep link do app", %{conn: conn} do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa)

    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros/convidar")

    html = lv |> element("form") |> render_submit(%{})

    assert html =~ "QR code do link de convite"
    assert html =~ "QR code do convite para o aplicativo"
    assert html =~ "Pelo aplicativo"
  end
end
