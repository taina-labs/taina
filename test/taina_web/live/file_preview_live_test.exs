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
    {:ok, _lv, html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.rkey}")

    assert html =~ "Esta casa é particular"
    assert html =~ "Pedir acesso"
  end

  test "requesting access creates the request and redirects to Pedidos", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, lv, _html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.rkey}")

    lv |> element(~s(button[phx-click="ask-access"])) |> render_click()

    assert {:error, {:live_redirect, %{to: "/conta/pedidos"}}} =
             lv |> element(~s(button[phx-click="request-access"])) |> render_click()

    assert {:ok, [request]} = Maraca.pedidos_recebidos(Scope.new(owner, tekoa))
    assert request.pedinte_id == other.id
    assert request.dono_id == owner.id
    assert request.recurso == file.rkey
    # sem campo na tela, o pedido vai sem motivo: o servidor nao fabrica frase
    assert request.motivo == nil
  end

  test "a tela de pedir acesso nomeia a pessoa, não um genérico", %{
    conn: conn,
    owner: owner,
    other: other,
    target_file: file
  } do
    name = owner.display_name || owner.username

    {:ok, lv, html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.rkey}")

    # o nome do dono (display ou username) na tela, não um "quem mora aqui",
    # e sem promessa de exclusividade: a dona pode ter aberto para outra pessoa
    assert html =~ "O arquivo é de #{name}."
    refute html =~ "Só #{name} vê este arquivo."

    lv |> element(~s(button[phx-click="ask-access"])) |> render_click()

    assert render(lv) =~ "Pedir acesso a #{name}?"
  end

  test "a readable file renders the preview, not the ask-access state", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, _} = Ybira.publicar_file(Scope.new(owner, tekoa), file.rkey)

    {:ok, _view, html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.rkey}")

    refute html =~ "Pedir acesso"
  end

  test "owner sees the publish control and readability line", %{conn: conn, owner: owner, target_file: file} do
    {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/arquivos/#{file.rkey}")

    assert html =~ "Só você, e quem você deixar."
    assert html =~ "Publicar"
  end

  test "owner publishes the file to the praca", %{conn: conn, tekoa: tekoa, owner: owner, target_file: file} do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/arquivos/#{file.rkey}")

    lv |> element(~s(button[phx-click="ask-zona"])) |> render_click()
    html = lv |> element(~s(button[phx-click="confirm-zona"])) |> render_click()

    assert html =~ "Publicado na praça."
    assert {:ok, updated} = Ybira.get_file(Scope.new(owner, tekoa), file.rkey)
    assert updated.zona == :praca
  end

  test "non-owner reader does not see the publish control", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    other: other,
    target_file: file
  } do
    {:ok, _} = Ybira.publicar_file(Scope.new(owner, tekoa), file.rkey)

    {:ok, lv, _html} = conn |> log_in(other) |> live(~p"/arquivos/#{file.rkey}")

    refute has_element?(lv, ~s(button[phx-click="ask-zona"]))
  end

  describe "voltar para a pasta do arquivo" do
    test "arquivo dentro de pasta volta para a pasta, não para o início", %{
      conn: conn,
      tekoa: tekoa,
      owner: owner
    } do
      scope = Scope.new(owner, tekoa)
      {:ok, folder} = Ybira.create_folder(scope, %{name: "Documentos"})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "dentro.txt"), folder_rkey: folder.rkey)

      {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/arquivos/#{file.rkey}")

      assert html =~ ~s(href="/arquivos/pasta/#{folder.rkey}")
    end

    test "arquivo solto na raiz volta para o início", %{conn: conn, owner: owner, target_file: file} do
      {:ok, _lv, html} = conn |> log_in(owner) |> live(~p"/arquivos/#{file.rkey}")

      assert html =~ ~s(href="/arquivos")
      refute html =~ "/arquivos/pasta/"
    end
  end
end
