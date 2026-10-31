defmodule TainaWeb.InviteCodeLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "rejects a link from another community after the LiveView connects", %{conn: conn} do
    conn = %{conn | host: "taina.local"}
    {:ok, lv, _html} = live(conn, ~p"/convite")

    lv
    |> form("#invite-code-form", %{"code" => "https://outra.comunidade/convite/abc123"})
    |> render_submit()

    assert render(lv) =~ "Esse convite é de outra comunidade."
    assert render(lv) =~ "outra.comunidade/convite/abc123"
  end
end
