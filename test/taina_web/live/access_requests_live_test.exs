defmodule TainaWeb.AccessRequestsLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa)
    requester = active_ava_fixture(tekoa, %{display_name: "Maria"})
    {:ok, file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())
    %{tekoa: tekoa, owner: owner, requester: requester, target_file: file}
  end

  defp request(requester, owner, file) do
    {:ok, req} = Maraca.request_access(requester, owner, "ybira_file", file.public_id, "Por favor")
    req
  end

  test "empty inbox shows the teaching copy", %{conn: conn, owner: owner} do
    {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert html =~ "Nenhum pedido por enquanto"
    assert html =~ "Ninguém acessa seus arquivos sem você deixar"
  end

  test "approving removes the row and flashes", %{conn: conn, owner: owner, requester: requester, target_file: file} do
    _req = request(requester, owner, file)
    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert html =~ "Maria"

    lv |> element(~s(button[phx-click="approve"])) |> render_click()

    html = render(lv)
    refute html =~ "Maria"
    assert html =~ "Acesso liberado"
    assert Maraca.authorize?(requester, :read, "ybira_file", file.public_id)
  end

  test "denying is gated by the confirm dialog then removes the row", %{
    conn: conn,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, owner, file)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    lv |> element(~s(button[phx-click="ask-deny"])) |> render_click()
    assert render(lv) =~ "Negar este pedido?"

    lv |> element(~s(#confirm-deny button[phx-click*="deny"])) |> render_click()

    html = render(lv)
    refute html =~ "Maria"
    assert html =~ "Pedido negado"
    refute Maraca.authorize?(requester, :read, "ybira_file", file.public_id)
  end

  test "an incoming request refreshes the inbox", %{conn: conn, owner: owner, requester: requester, target_file: file} do
    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")
    refute html =~ "Maria"

    _req = request(requester, owner, file)

    assert render(lv) =~ "Maria"
  end

  test "the Conta nav shows the pending dot when there is an open request", %{
    conn: conn,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, owner, file)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert has_element?(lv, "a[aria-label*='há pedidos esperando'] .nav-dot")
  end

  test "the Conta nav has no dot when nothing is waiting", %{conn: conn, owner: owner} do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    refute has_element?(lv, ".nav-dot")
  end
end
