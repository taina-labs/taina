defmodule TainaWeb.MuralLiveTest do
  @moduledoc """
  Tela do mural (docs/web-revamp-spec.md 6.4): frases simples de quem fez o
  quê, do mais recente para o mais antigo, somente leitura para todos os
  papéis (zelador incluso). Cada linha leva o próprio dia no meta ("Hoje,
  09:12") e a lista acaba no "Fim do mural.". Um teste por board do Penpot:
  `padrao`, `vazio` e `degradado` (este no componente puro do corpo, já que
  as chamadas de contexto não falham sob demanda), mais a paginação que
  termina.
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa, %{display_name: "Ana"})

    %{tekoa: tekoa, zelador: zelador, morador: active_ava_fixture(tekoa, %{display_name: "Bruno"})}
  end

  # board `padrao`
  test "atos públicos viram linhas com o dia no meta, e a lista acaba no 'Fim do mural.'", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador
  } do
    scope = Scope.new(zelador, tekoa)
    path = tmp_upload_fixture("conteúdo", "estatuto.pdf")
    {:ok, file} = Ybira.upload(scope, path, filename: "estatuto.pdf")
    {:ok, _file} = Ybira.publicar_file(scope, file.rkey)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    # as linhas são ListRow mural, quadradinho à esquerda
    assert html =~ "list-row--mural"
    assert html =~ "service-square--mural"
    assert html =~ "Ana publicou estatuto.pdf na praça"
    refute html =~ "Ana guardou estatuto.pdf na caixa"

    # o meta do board: dia e hora juntos, "Hoje, 09:12"
    assert html =~ ~r/Hoje, \d{2}:\d{2}/

    # uma página só: a lista já acabou, o "Fim do mural." assume
    assert html =~ "Fim do mural."
  end

  # board `vazio`
  test "mural vazio ensina o que ele é", %{conn: conn, morador: morador} do
    {:ok, _lv, html} = conn |> log_in(morador) |> live(~p"/mural")

    assert html =~ "empty-state"
    assert html =~ "Nada no mural ainda"
    assert html =~ "Ainda não aconteceu nada por aqui. Quando alguém publicar na praça ou cuidar da máquina"
  end

  # board `degradado` (componente puro: o contexto não falha sob demanda)
  test "degradado: cartão de erro no topo e esqueleto no lugar das linhas", %{conn: _conn} do
    html =
      render_component(&TainaWeb.MuralLive.mural_body/1, %{
        load_error: true,
        entries: [],
        event_count: 0,
        next_offset: nil,
        more_error: false
      })

    assert html =~ "error-card"
    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert html =~ "Tentar de novo"
    assert html =~ "Falar com quem cuida"

    # as linhas que não carregaram esqueletam, não somem em silêncio
    assert html =~ "skeleton--list-row"
  end

  test "verbos do kernel viram frases com quem fez e quando", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    scope = Scope.new(zelador, tekoa)
    path = tmp_upload_fixture("conteúdo", "estatuto.pdf")
    {:ok, file} = Ybira.upload(scope, path, filename: "estatuto.pdf")
    {:ok, _file} = Ybira.publicar_file(scope, file.rkey)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Ana publicou estatuto.pdf na praça"
    refute html =~ "Ana guardou estatuto.pdf na caixa"
    assert html =~ ~r/\d{2}:\d{2}/
  end

  test "concessão fica na auditoria, fora da projeção pública do mural", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador,
    morador: morador
  } do
    scope = Scope.new(zelador, tekoa)
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("conteúdo", "ata.txt"))
    {:ok, _grant} = Maraca.conceder(scope, "ypy.file.v0", file.rkey, morador)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    refute html =~ "Ana abriu a casa para Bruno"
  end

  test "zelador vê o mesmo mural, sem controle nenhum sobre o registro", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    :ok = Maraca.record_event(Scope.new(zelador, tekoa), :invite_created, %{"role" => "morador"})

    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    refute html =~ "Ana convidou uma nova pessoa para a comunidade"
    # Somente leitura: sem um único controle na tela.
    refute has_element?(lv, "#mural-events button")
    refute has_element?(lv, "#mural-events a")
    refute has_element?(lv, "#mural-events input")
  end

  test "aceite de convite de zelador diz que a pessoa entrou para cuidar da máquina", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador
  } do
    assert {:ok, %{token: token}} = Maraca.invite_user(zelador, tekoa, role: :zelador)

    assert {:ok, _accepted} =
             Maraca.accept_invite(token, %{
               "username" => "joana",
               "display_name" => "Joana",
               "password" => "senhasegura123",
               "password_confirmation" => "senhasegura123"
             })

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Joana entrou na comunidade para cuidar da máquina"
  end

  test "revogação de convite fica fora da projeção pública", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador
  } do
    :ok = Maraca.record_event(Scope.new(zelador, tekoa), :invite_revoked, %{"role" => "zelador"})

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    refute html =~ "Ana revogou um convite para cuidar da máquina"
  end

  test "aceite antigo (sem papel no registro) continua com a frase genérica", %{
    conn: conn,
    tekoa: tekoa,
    morador: morador
  } do
    :ok = Maraca.record_event(Scope.new(morador, tekoa), :invite_accepted, %{})

    {:ok, _lv, html} = conn |> log_in(morador) |> live(~p"/mural")

    assert html =~ "Bruno entrou na comunidade"
  end

  test "link de nova senha fica fora da projeção pública", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador,
    morador: morador
  } do
    scope = Scope.new(zelador, tekoa)
    assert {:ok, _} = Maraca.mint_reset_link(scope, morador)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    refute html =~ "Ana gerou um link de nova senha para Bruno"
  end

  test "atos do zelador sobre papéis viram frases de cuidado da máquina", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador,
    morador: morador
  } do
    scope = Scope.new(zelador, tekoa)

    assert {:ok, _} = Maraca.update_member_role(scope, morador.public_id, :zelador)
    assert {:ok, _} = Maraca.deactivate_member(scope, morador.public_id)
    assert {:ok, _} = Maraca.reactivate_member(scope, morador.public_id)
    assert {:ok, _} = Maraca.update_member_role(scope, morador.public_id, :morador)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    # A troca de papel e verbo do kernel: o payload da cadeia nomina o papel,
    # nao a pessoa (a projecao de nomes cobre o ator). Desativar e reativar
    # sao atos do produto e nomeiam a pessoa.
    assert html =~ "Ana deu a um morador o cuidado da máquina"
    assert html =~ "Ana desativou a conta de Bruno"
    assert html =~ "Ana reativou a conta de Bruno"
    assert html =~ "Ana tirou de um morador o cuidado da máquina"
  end

  test "pagina com 'Carregando mais' e acaba no 'Fim do mural.'", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    # 55 atos do zelador: a primeira página (50) deixa resto.
    scope = Scope.new(zelador, tekoa)

    for i <- 1..55 do
      :ok = Maraca.record_event(scope, :quota_changed, %{"to" => i})
    end

    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Carregando mais..."
    refute html =~ "Fim do mural."

    html = render_hook(lv, "load-more")

    refute html =~ "Carregando mais..."
    assert html =~ "mudou o limite de armazenamento para"
    assert html =~ "Fim do mural."
  end

  test "Mural renderiza a casca page com o título no cabeçalho (a casca é quem possui o título)", %{
    conn: conn,
    morador: morador
  } do
    {:ok, lv, _html} = conn |> log_in(morador) |> live(~p"/mural")

    assert has_element?(lv, ".page-header__title", "Mural")
  end
end
