defmodule TainaWeb.MembersLiveTest do
  @moduledoc """
  Moradores (spec 6.4, boards do Penpot): `morador`
  cc1037dc-e8ab-80cc-8008-d5e1bc7a5a02 (lista com busca, sem ação),
  `zelador` cc1037dc-e8ab-80cc-8008-d5e1c8a5c025 (Convidar no cabeçalho),
  `busca vazia` cc1037dc-e8ab-80cc-8008-d5e1cd378b7e
  ("Ninguém com esse nome") e `acoes da pessoa`
  cc1037dc-e8ab-80cc-8008-d5e1d5f3b551 (menu com o link de redefinição). Os
  convites pendentes ficam em seção própria, com revogação.
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca

  setup do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa, %{username: "ana", display_name: "Ana Oliveira"})
    member = active_ava_fixture(tekoa, %{username: "joao", display_name: "João Mendes"})
    %{tekoa: tekoa, zelador: zelador, member: member}
  end

  test "morador: lista com papel e ano de entrada, sem ação de convidar", %{conn: conn, member: member} do
    {:ok, lv, html} = conn |> log_in(member) |> live(~p"/moradores")

    assert html =~ "Ana Oliveira"
    assert html =~ "João Mendes"
    # meta do board: papel + ano em que a pessoa entrou
    assert html =~ "Zelador(a), entrou em"
    assert has_element?(lv, ".list-row--person", "João Mendes")
    assert has_element?(lv, "input[placeholder=\"Buscar pessoa\"]")
    refute has_element?(lv, ".list-row__chevron")

    refute html =~ "/moradores/convidar"
    # morador não vê o menu de ações nem um rodapé de papel
    refute html =~ "Ações da conta"
    refute html =~ "badge--zelador"
  end

  test "morador não vê convites pendentes", %{conn: conn, tekoa: tekoa, zelador: zelador, member: member} do
    {:ok, _invite} = Maraca.invite_user(zelador, tekoa)

    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/moradores")

    refute html =~ "Convites pendentes"
    refute html =~ "Convite pendente"
  end

  test "zelador: Convidar no cabeçalho volta para Moradores sem rodapé de papel", %{conn: conn, zelador: zelador} do
    {:ok, lv, html} = conn |> log_in(zelador) |> live("/moradores?filtro=zeladores")

    assert has_element?(
             lv,
             ~S(.page-header a[href="/moradores/convidar?return_to=%2Fmoradores%3Ffiltro%3Dzeladores"]),
             "Convidar"
           )

    refute html =~ "badge--zelador"
    refute html =~ "Quem cuida da nuvem só convida pessoas"
  end

  test "busca filtra a lista", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores")

    html = lv |> element("#member-search-form") |> render_change(%{"query" => "joão"})

    assert html =~ "João Mendes"
    refute html =~ "Ana Oliveira"
  end

  test "busca vazia: Ninguém com esse nome", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores")

    html = lv |> element("#member-search-form") |> render_change(%{"query" => "Julia"})

    assert has_element?(lv, ".empty-state", "Ninguém com esse nome")
    assert html =~ "Confira a escrita ou procure por outro nome."
    refute html =~ "João Mendes"
  end

  test "ações da pessoa: o zelador abre o menu e gera o link de redefinição", %{
    conn: conn,
    zelador: zelador,
    member: member
  } do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores")

    menu = lv |> element("#member-menu-#{member.public_id}") |> render()

    # o board não traz troca de papel nem desativação: o menu oferta o que a
    # caixa faz hoje (e o resto da assembleia chega depois do MVP)
    assert menu =~ "Gerar link de redefinição de senha"
    refute menu =~ "Tornar zelador(a)"
    refute menu =~ "Desativar conta"

    html =
      lv
      |> element(~s(button[phx-click*="reset_link"][phx-click*="#{member.public_id}"]))
      |> render_click()

    assert html =~ "Link de redefinição de senha"
    assert html =~ "/redefinir/"

    assert has_element?(
             lv,
             ~S(#reset-link-modal .dialog__panel[aria-labelledby="reset-link-modal-title"] h2#reset-link-modal-title)
           )
  end

  test "a própria conta do zelador não ganha menu de ações", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores")

    refute has_element?(lv, "#member-menu-#{zelador.public_id}")
  end

  test "convite pendente aparece em seção própria, com revogação", %{
    conn: conn,
    zelador: zelador,
    tekoa: tekoa
  } do
    {:ok, _invited} = Maraca.invite_user(zelador, tekoa)

    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/moradores")

    assert html =~ "Convites pendentes"
    assert has_element?(lv, ".actions-menu", "Revogar convite")
    refute has_element?(lv, ".badge--inactive svg")
    assert html =~ "aguardando a pessoa aceitar"
  end

  test "zelador revoga um convite pendente", %{conn: conn, zelador: zelador, tekoa: tekoa} do
    {:ok, %{ava: invited}} = Maraca.invite_user(zelador, tekoa)

    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores")

    html =
      lv
      |> element(~s(button[phx-click*="ask_revoke"][phx-click*="#{invited.public_id}"]))
      |> render_click()

    assert html =~ "Revogar este convite?"

    html = lv |> element(~S(#confirm-revoke button[phx-click*="revoke"])) |> render_click()

    assert html =~ "Convite revogado."
    refute html =~ "Convites pendentes"
  end
end
