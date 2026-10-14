defmodule TainaWeb.AccessRequestsLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa, %{display_name: "Joana"})
    requester = active_ava_fixture(tekoa, %{display_name: "Maria"})
    {:ok, file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())
    %{tekoa: tekoa, owner: owner, requester: requester, target_file: file}
  end

  defp request(requester, tekoa, file) do
    {:ok, req} = Maraca.pedir_acesso(Scope.new(requester, tekoa), "ypy.file.v0", file.rkey, "Por favor")
    req
  end

  test "empty inbox shows the teaching copy", %{conn: conn, owner: owner} do
    {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert html =~ "Nenhum pedido por enquanto"
    assert html =~ "Ninguém acessa seus arquivos sem você deixar"
  end

  test "approving removes the pending row and shows the grant as reversible", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert html =~ "Maria"

    lv |> element(~s(button[phx-click="approve"])) |> render_click()

    html = render(lv)
    assert html =~ "Acesso a doc.txt liberado"
    assert html =~ "Já liberados"
    assert html =~ "doc.txt, desde"
    refute html =~ "pediu acesso"
    assert Maraca.authorize?(requester, :read, "ypy.file.v0", file.rkey)
  end

  test "a granted permission can be revoked from the Já liberados section", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    lv |> element(~s(button[phx-click="approve"])) |> render_click()
    assert render(lv) =~ "Tirar acesso"

    lv |> element(~s(button[phx-click="ask-revoke"])) |> render_click()
    assert render(lv) =~ "Tirar o acesso de Maria?"
    assert render(lv) =~ "Para abrir de novo, ela precisa pedir."

    lv |> element(~s(#confirm-revoke button[phx-click*="revoke"])) |> render_click()

    html = render(lv)
    assert html =~ "Acesso de Maria tirado"
    refute has_element?(lv, ~s(button[phx-click="ask-revoke"]))
    assert html =~ "Nenhum pedido por enquanto"
    refute Maraca.authorize?(requester, :read, "ypy.file.v0", file.rkey)
  end

  test "denying is gated by the confirm dialog then removes the row", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    lv |> element(~s(button[phx-click="ask-deny"])) |> render_click()
    assert render(lv) =~ "Negar este pedido?"

    lv |> element(~s(#confirm-deny button[phx-click*="deny"])) |> render_click()

    html = render(lv)
    refute html =~ "Maria"
    assert html =~ "Pedido negado"
    refute Maraca.authorize?(requester, :read, "ypy.file.v0", file.rkey)
  end

  test "an incoming request refreshes the inbox", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")
    refute html =~ "Maria"

    _req = request(requester, tekoa, file)

    assert render(lv) =~ "Maria"
  end

  test "the Conta nav shows the pending dot when there is an open request", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert has_element?(lv, "a[aria-label*='há pedidos esperando'] .nav-dot")
  end

  test "the Conta nav has no dot when nothing is waiting", %{conn: conn, owner: owner} do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    refute has_element?(lv, ".nav-dot")
  end

  describe "pedidos enviados" do
    test "empty screen shows the teaching copy", %{conn: conn, requester: requester} do
      {:ok, _lv, html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

      assert html =~ "Nenhum pedido por enquanto"
    end

    test "lists a pending request waiting on the owner", %{
      conn: conn,
      tekoa: tekoa,
      requester: requester,
      target_file: file
    } do
      _req = request(requester, tekoa, file)
      {:ok, _lv, html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

      assert html =~ "Seus pedidos"
      assert html =~ "Joana"
      assert html =~ "esperando"
    end

    test "an approved request shows the liberation line instead of vanishing", %{
      conn: conn,
      tekoa: tekoa,
      owner: owner,
      requester: requester,
      target_file: file
    } do
      req = request(requester, tekoa, file)
      {:ok, _} = Maraca.aprovar(Scope.new(owner, tekoa), req)
      {:ok, _lv, html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

      assert html =~ "Já decididos"
      assert html =~ "doc.txt: Joana liberou. Você já pode abrir."
      refute html =~ "esperando"
    end

    test "a denied request shows the refusal line and invites trying again", %{
      conn: conn,
      tekoa: tekoa,
      owner: owner,
      requester: requester,
      target_file: file
    } do
      req = request(requester, tekoa, file)
      {:ok, _} = Maraca.negar(Scope.new(owner, tekoa), req)
      {:ok, _lv, html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

      assert html =~ "Já decididos"
      assert html =~ "doc.txt: Joana recusou este pedido. Você pode pedir de novo quando quiser."
    end

    test "approval refreshes the list and flashes", %{
      conn: conn,
      tekoa: tekoa,
      owner: owner,
      requester: requester,
      target_file: file
    } do
      req = request(requester, tekoa, file)
      {:ok, lv, _html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

      {:ok, _} = Maraca.aprovar(Scope.new(owner, tekoa), req)

      html = render(lv)
      assert html =~ "Pedido aprovado"
      refute html =~ "esperando"
      assert html =~ "Já decididos"
      assert html =~ "Joana liberou"
    end

    test "denial refreshes the list and flashes", %{
      conn: conn,
      tekoa: tekoa,
      owner: owner,
      requester: requester,
      target_file: file
    } do
      req = request(requester, tekoa, file)
      {:ok, lv, _html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

      {:ok, _} = Maraca.negar(Scope.new(owner, tekoa), req)

      html = render(lv)
      assert html =~ "Seu pedido foi negado"
      refute html =~ "esperando"
      assert html =~ "Joana recusou este pedido"
    end
  end
end
