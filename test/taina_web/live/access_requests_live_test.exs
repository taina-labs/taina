defmodule TainaWeb.AccessRequestsLiveTest do
  @moduledoc """
  Pedidos (spec 6.4, boards do Penpot): `vazio`
  cc1037dc-e8ab-80cc-8008-d5e22b5109c1 ("Nenhum pedido ainda"), `com pedidos`
  cc1037dc-e8ab-80cc-8008-d5e227df15d9 (pendente com Recusar/Dar acesso,
  concedido e recusado com o estado na linha) e `enviado`
  cc1037dc-e8ab-80cc-8008-d62898a2525a (quem pediu vê a confirmação).
  """

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

  # board `vazio`
  test "empty inbox shows the teaching copy", %{conn: conn, owner: owner} do
    {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert html =~ "Nenhum pedido ainda"
    assert html =~ "Quando alguém pedir para abrir um arquivo da sua casa, aparece aqui."
  end

  # board `com pedidos`: pendente
  test "a pending request shows the person, the reason and the row actions", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    assert has_element?(lv, ".list-row--pedido", "Maria pediu acesso")
    assert html =~ "doc.txt, hoje"
    assert html =~ "Motivo: Por favor"
    assert has_element?(lv, ~s(button[phx-click="ask-deny"]), "Recusar")
    assert has_element?(lv, ~s(button[phx-click="approve"]), "Dar acesso")
  end

  # board `com pedidos`: decidido
  test "approving turns the row into a reversible grant", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    lv |> element(~s(button[phx-click="approve"])) |> render_click()

    html = render(lv)
    assert html =~ "Acesso a doc.txt liberado"
    assert has_element?(lv, ".list-row--dado", "Maria recebeu acesso")
    assert html =~ "Acesso dado em"
    assert has_element?(lv, ~s(button[phx-click="ask-revoke"]), "Tirar acesso")
    assert html =~ "Os pedidos resolvidos ficam visíveis. Você pode mudar de ideia quando quiser."
    assert Maraca.authorize?(requester, :read, "ypy.file.v0", file.rkey)
  end

  test "a granted permission can be revoked from its row", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    lv |> element(~s(button[phx-click="approve"])) |> render_click()
    lv |> element(~s(button[phx-click="ask-revoke"])) |> render_click()
    assert render(lv) =~ "Tirar o acesso de Maria?"
    assert render(lv) =~ "Para abrir de novo, ela precisa pedir."

    lv |> element(~s(#confirm-revoke button[phx-click*="revoke"])) |> render_click()

    html = render(lv)
    assert html =~ "Acesso de Maria tirado"
    refute has_element?(lv, ~s(button[phx-click="ask-revoke"]))
    assert html =~ "Nenhum pedido ainda"
    refute Maraca.authorize?(requester, :read, "ypy.file.v0", file.rkey)
  end

  test "confirming a grant that was already revoked refreshes without a nested reply", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    req = request(requester, tekoa, file)
    {:ok, grant} = Maraca.aprovar(Scope.new(owner, tekoa), req)
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    lv |> element(~s(button[phx-click="ask-revoke"])) |> render_click()
    {:ok, _revoked} = Maraca.revogar(Scope.new(owner, tekoa), grant)

    lv |> element(~s(#confirm-revoke button[phx-click*="revoke"])) |> render_click()

    html = render(lv)
    assert html =~ "Este acesso já foi tirado."
    refute has_element?(lv, ~s(button[phx-click="ask-revoke"]))
    refute Maraca.authorize?(requester, :read, "ypy.file.v0", file.rkey)
  end

  test "confirming a grant that is no longer listed refreshes without a nested reply", %{
    conn: conn,
    owner: owner
  } do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/conta/pedidos")

    render_click(lv, "ask-revoke", %{"id" => "missing-grant"})
    lv |> element(~s(#confirm-revoke button[phx-click*="revoke"])) |> render_click()

    html = render(lv)
    assert html =~ "Este acesso já foi tirado."
    refute has_element?(lv, "#confirm-revoke")
    assert html =~ "Nenhum pedido ainda"
  end

  # board `com pedidos`: recusado
  test "denying is gated by the confirm dialog and the refusal reaches who asked", %{
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
    assert html =~ "Pedido negado"
    # o dono também vê a recusa na seção decidida (board: "teve o acesso recusado")
    assert html =~ "Maria teve o acesso recusado"
    assert html =~ "Acesso recusado em"
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
    assert html =~ "Nenhum pedido ainda"

    _req = request(requester, tekoa, file)

    assert render(lv) =~ "Maria pediu acesso"
  end

  # board `enviado`: quem pediu acompanha a resposta por aqui
  test "the requester sees the sent confirmation while waiting", %{
    conn: conn,
    tekoa: tekoa,
    owner: _owner,
    requester: requester,
    target_file: file
  } do
    _req = request(requester, tekoa, file)
    {:ok, _lv, html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

    assert html =~ "Pedido enviado"
    assert html =~ "Joana vai decidir. Você vê a resposta aqui em Pedidos."
    refute html =~ "Dar acesso"
  end

  test "approval reaches the requester as a flash, not silence", %{
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
    assert html =~ "Pedido aprovado: agora você pode abrir doc.txt."
    assert has_element?(lv, ".list-row--dado", "Joana liberou o acesso")
  end

  test "revoked access is not shown as currently released", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    requester: requester,
    target_file: file
  } do
    req = request(requester, tekoa, file)
    {:ok, grant} = Maraca.aprovar(Scope.new(owner, tekoa), req)
    {:ok, _revoked} = Maraca.revogar(Scope.new(owner, tekoa), grant)

    {:ok, lv, html} = conn |> log_in(requester) |> live(~p"/conta/pedidos")

    assert html =~ "Nenhum pedido ainda"
    refute has_element?(lv, ".list-row--dado", "Joana liberou o acesso")
  end

  test "denial reaches the requester as a flash and a line", %{
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
    assert html =~ "Seu pedido foi negado."
    assert has_element?(lv, ".list-row--recusado", "Joana recusou o pedido")
  end
end
