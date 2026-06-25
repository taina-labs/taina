defmodule TainaWeb.FilePreviewLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa)
    other = active_ava_fixture(tekoa)
    {:ok, file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture("oi", "particular.txt"))
    %{tekoa: tekoa, owner: owner, other: other, target_file: file}
  end

  test "forbidden casa renders the ask-access state", %{conn: conn, other: other, target_file: file} do
    {:ok, _lv, html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.public_id}")

    assert html =~ "Esta casa é particular"
    assert html =~ "Pedir acesso"
  end

  test "requesting access creates the request and redirects to Meus pedidos", %{
    conn: conn,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, lv, _html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.public_id}")

    lv |> element(~s(button[phx-click="ask-access"])) |> render_click()

    assert {:error, {:live_redirect, %{to: "/conta/meus-pedidos"}}} =
             lv |> element(~s(button[phx-click="request-access"])) |> render_click()

    assert [request] = Maraca.list_access_requests(owner)
    assert request.requester_id == other.id
    assert request.owner_id == owner.id
    assert request.resource_id == file.public_id
  end

  test "a readable file renders the preview, not the ask-access state", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, _} = Ybira.publicar_file(Scope.new(owner, tekoa), file.public_id)

    {:ok, _view, html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.public_id}")

    refute html =~ "Pedir acesso"
  end

  test "owner sees the publish control and readability line", %{conn: conn, owner: owner, target_file: file} do
    {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/arquivos/#{file.public_id}")

    assert html =~ "Só você, e quem você deixar."
    assert html =~ "Publicar na praça"
  end

  test "owner publishes the file to the praca", %{conn: conn, tekoa: tekoa, owner: owner, target_file: file} do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/arquivos/#{file.public_id}")

    lv |> element(~s(button[phx-click="ask-zona"])) |> render_click()
    html = lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

    assert html =~ "Publicado na praça."
    assert {:ok, updated} = Ybira.get_file(Scope.new(owner, tekoa), file.public_id)
    assert updated.zona == :praca
  end

  test "non-owner reader does not see the publish control", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, _} = Ybira.publicar_file(Scope.new(owner, tekoa), file.public_id)

    {:ok, lv, _html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.public_id}")

    refute has_element?(lv, ~s(button[phx-click="ask-zona"]))
  end
end
