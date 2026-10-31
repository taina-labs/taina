defmodule TainaWeb.AccountLiveTest do
  @moduledoc """
  Conta (spec 6.4, boards do Penpot): `morador`
  cc1037dc-e8ab-80cc-8008-d5e23c048bf9, `zelador`
  cc1037dc-e8ab-80cc-8008-d5e261192f2d e W cc1037dc-e8ab-80cc-8008-d5eaef8a5541.
  Cartão da pessoa, linhas do dia a dia (Pedidos com a meta viva, Privacidade,
  Convidar para quem cuida, Trocar senha no sheet, Dispositivos com revogação)
  e o Sair.
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture(%{name: "Quilombo do Café"})
    zelador = zelador_fixture(tekoa, %{username: "ana", display_name: "Ana Oliveira"})
    member = active_ava_fixture(tekoa, %{username: "joao", display_name: "João Mendes"})
    %{tekoa: tekoa, zelador: zelador, member: member}
  end

  test "morador: cartão da pessoa e as linhas do board, sem Convidar", %{conn: conn, member: member} do
    {:ok, lv, html} = conn |> log_in(member) |> live(~p"/conta")

    # cartão da pessoa: avatar, nome, papel e comunidade (board)
    assert has_element?(lv, ".card .avatar", "J")
    assert html =~ "João Mendes"
    assert html =~ "Morador(a), Quilombo do Café"

    # as linhas do board, com a meta dele
    assert has_element?(lv, ".list-row--civic", "Pedidos")
    assert has_element?(lv, ".list-row--civic", "Privacidade")
    assert has_element?(lv, ".list-row--civic", "Trocar senha")
    assert has_element?(lv, ".list-row--civic", "Dispositivos")
    assert html =~ "Como funciona o acesso"
    assert html =~ "Atualize a sua senha"
    assert html =~ "Aparelhos com acesso"

    # o board tirou daqui: Lixeira, Moradores, Armazenamento e Convites
    refute html =~ "Lixeira"
    refute html =~ "Armazenamento"
    refute html =~ "/moradores/convidar"

    # Sair é o botão secundário com o ícone sair
    assert has_element?(lv, ~s(a[href="/logout"][data-method="delete"], button[data-method="delete"]), "Sair")
  end

  test "zelador: a linha Convidar entra entre Privacidade e Trocar senha", %{conn: conn, zelador: zelador} do
    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/conta")

    assert has_element?(lv, ~s(.list-row a[href="/moradores/convidar"]), "Convidar")
    assert html =~ "Criar um convite"
    assert html =~ "Zelador(a), Quilombo do Café"
  end

  test "a meta de Pedidos vive: Nada pendente quando a fila está vazia", %{conn: conn, member: member} do
    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/conta")

    assert html =~ "Nada pendente"
  end

  test "a meta de Pedidos conta solicitações recebidas como resposta pendente", %{
    conn: conn,
    tekoa: tekoa,
    member: member,
    zelador: zelador
  } do
    {:ok, file} = Ybira.upload(Scope.new(member, tekoa), tmp_upload_fixture())
    {:ok, _pedido} = Maraca.pedir_acesso(Scope.new(zelador, tekoa), "ypy.file.v0", file.rkey, "Preciso ler")

    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/conta")

    assert html =~ "1 esperando sua resposta"
  end

  test "a meta de Pedidos identifica solicitações enviadas", %{
    conn: conn,
    tekoa: tekoa,
    member: member,
    zelador: zelador
  } do
    {:ok, file} = Ybira.upload(Scope.new(zelador, tekoa), tmp_upload_fixture())
    {:ok, _pedido} = Maraca.pedir_acesso(Scope.new(member, tekoa), "ypy.file.v0", file.rkey, "Preciso ler")

    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/conta")

    assert html =~ "1 pedido enviado"
    refute html =~ "esperando sua resposta"
  end

  test "trocar senha abre o sheet com o formulário e valida a senha atual", %{conn: conn, member: member} do
    {:ok, lv, _html} = conn |> log_in(member) |> live(~p"/conta")

    lv |> element(~s([phx-click="open-password"])) |> render_click()

    assert has_element?(lv, "#password-sheet .sheet__panel")
    assert render(lv) =~ "Confirme com a senha que você usa hoje"

    html =
      render_submit(lv, "change-password", %{
        "account" => %{
          "current_password" => "errada",
          "new_password" => "frase-longa-nova",
          "password_confirmation" => "frase-longa-nova"
        }
      })

    assert html =~ "Não é a sua senha atual. Confira e tente de novo."
  end

  test "trocar senha no sheet troca de verdade e derruba os aparelhos", %{conn: conn, tekoa: tekoa, member: member} do
    {:ok, lv, _html} = conn |> log_in(member) |> live(~p"/conta")

    lv |> element(~s([phx-click="open-password"])) |> render_click()

    html =
      render_submit(lv, "change-password", %{
        "account" => %{
          "current_password" => "senhasegura123",
          "new_password" => "frase-longa-nova",
          "password_confirmation" => "frase-longa-nova"
        }
      })

    assert html =~ "Senha trocada. Da próxima vez, entre com a senha nova."
    refute has_element?(lv, "#password-sheet .sheet__panel")
    assert match?({:ok, _ava}, Maraca.authenticate(member.username, "frase-longa-nova", tekoa))
  end

  test "dispositivos: o sheet lista os aparelhos com acesso e revoga", %{conn: conn, tekoa: tekoa, member: member} do
    scope = Scope.new(member, tekoa)
    {:ok, %{device: _device}} = Maraca.create_device_token(scope, "Celular de João")

    {:ok, lv, _html} = conn |> log_in(member) |> live(~p"/conta")

    lv |> element(~s([phx-click="open-devices"])) |> render_click()

    assert has_element?(lv, "#devices-sheet .sheet__panel", "Celular de João")

    html = lv |> element(~s(button[phx-click="revoke-device"])) |> render_click()

    assert html =~ "Acesso do aparelho revogado."
    refute has_element?(lv, "#devices-sheet", "Celular de João")
  end

  test "dispositivos sem aparelho diz com honestidade que a lista está vazia", %{conn: conn, member: member} do
    {:ok, lv, _html} = conn |> log_in(member) |> live(~p"/conta")

    lv |> element(~s([phx-click="open-devices"])) |> render_click()

    assert has_element?(lv, "#devices-sheet", "Nenhum aparelho com acesso agora.")
  end
end
