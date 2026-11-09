defmodule TainaWeb.InviteDeepLinkTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias TainaWeb.InviteLink

  @moduletag capture_log: true

  test "zelador ve os dois QR: o link da web e o deep link do app", %{conn: conn} do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa)

    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores/convidar")

    html = lv |> element("form") |> render_submit(%{})

    assert html =~ "QR code do link de convite"
    assert html =~ "QR code do convite para o aplicativo"
    assert html =~ "Pelo aplicativo"

    assert [_, token] =
             Regex.run(~r{<p class="type-mono-sm qr-card__link">https?://[^<]*/convite/([^<]+)</p>}, html)

    app_link = InviteLink.deep_link(token)
    app_qr = app_link |> EQRCode.encode() |> EQRCode.svg(viewbox: true)
    rects = app_qr |> then(&Regex.scan(~r/<rect\b[^>]*\/>/, &1)) |> List.flatten()

    assert rects != []

    assert Enum.all?(rects, fn rect ->
             html =~ String.replace_suffix(rect, "/>", ">")
           end)
  end
end
