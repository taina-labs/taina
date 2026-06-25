defmodule TainaWeb.MyRequestsLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa, %{display_name: "Joana"})
    requester = active_ava_fixture(tekoa)
    {:ok, file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())
    %{tekoa: tekoa, owner: owner, requester: requester, target_file: file}
  end

  defp request(requester, owner, file) do
    {:ok, req} = Maraca.request_access(requester, owner, "ybira_file", file.public_id, "Por favor")
    req
  end

  test "empty list shows the teaching copy", %{conn: conn, requester: requester} do
    {:ok, _lv, html} = conn |> log_in(requester) |> live(~p"/conta/meus-pedidos")

    assert html =~ "Você não tem pedidos abertos"
  end

  test "lists a pending request waiting on the owner", %{
    conn: conn,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, owner, file)
    {:ok, _lv, html} = conn |> log_in(requester) |> live(~p"/conta/meus-pedidos")

    assert html =~ "Joana"
    assert html =~ "Esperando"
  end

  test "approval refreshes the list and flashes", %{conn: conn, owner: owner, requester: requester, target_file: file} do
    req = request(requester, owner, file)
    {:ok, lv, _html} = conn |> log_in(requester) |> live(~p"/conta/meus-pedidos")

    {:ok, _} = Maraca.approve_access_request(owner, req.id)

    html = render(lv)
    assert html =~ "Seu pedido foi aprovado"
    refute html =~ "Joana"
  end

  test "denial refreshes the list and flashes", %{conn: conn, owner: owner, requester: requester, target_file: file} do
    req = request(requester, owner, file)
    {:ok, lv, _html} = conn |> log_in(requester) |> live(~p"/conta/meus-pedidos")

    {:ok, _} = Maraca.deny_access_request(owner, req.id)

    html = render(lv)
    assert html =~ "Seu pedido foi negado"
    refute html =~ "Joana"
  end
end
