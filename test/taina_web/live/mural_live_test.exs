defmodule TainaWeb.MuralLiveTest do
  @moduledoc """
  Tela do mural: frases simples de quem fez o quê, agrupadas por dia,
  somente leitura para todos os papéis (zelador incluso). O registro é a
  projecao da cadeia unica: atos do produto e verbos do kernel.
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

  test "mural vazio ensina o que ele é e que é registro permanente", %{conn: conn, morador: morador} do
    {:ok, _lv, html} = conn |> log_in(morador) |> live(~p"/mural")

    assert html =~ "Mural"
    assert html =~ "Nada aconteceu ainda"
    assert html =~ "Ninguém edita e ninguém apaga"
  end

  test "verbos do kernel viram frases com quem fez e quando", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    scope = Scope.new(zelador, tekoa)
    path = tmp_upload_fixture("conteúdo", "estatuto.pdf")
    {:ok, file} = Ybira.upload(scope, path, filename: "estatuto.pdf")
    {:ok, _file} = Ybira.publicar_file(scope, file.rkey)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Ana guardou um arquivo na caixa."
    assert html =~ "Ana publicou um arquivo na praça."
    # sob "Hoje"/"Ontem" a hora basta: o dia nao se repete em cada linha
    assert html =~ "Hoje"
    assert html =~ ~r/\d{2}:\d{2}/
    refute html =~ "hoje"
  end

  test "zelador vê o mesmo mural, sem controle nenhum sobre o registro", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    :ok = Maraca.record_event(Scope.new(zelador, tekoa), :invite_created, %{"role" => "morador"})

    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Ana convidou uma nova pessoa para a comunidade."
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

    assert html =~ "Joana entrou na comunidade para cuidar da máquina."
  end

  test "revogação de convite nomeia o cuidado da máquina", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador
  } do
    :ok = Maraca.record_event(Scope.new(zelador, tekoa), :invite_revoked, %{"role" => "zelador"})

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Ana revogou um convite para cuidar da máquina."
  end

  test "aceite antigo (sem papel no registro) continua com a frase genérica", %{
    conn: conn,
    tekoa: tekoa,
    morador: morador
  } do
    :ok = Maraca.record_event(Scope.new(morador, tekoa), :invite_accepted, %{})

    {:ok, _lv, html} = conn |> log_in(morador) |> live(~p"/mural")

    assert html =~ "Bruno entrou na comunidade."
  end

  test "link de nova senha vira frase com quem gerou e para quem", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador,
    morador: morador
  } do
    scope = Scope.new(zelador, tekoa)
    assert {:ok, _} = Maraca.mint_reset_link(scope, morador)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Ana gerou um link de nova senha para Bruno."
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
    assert html =~ "Ana deu a um morador o cuidado da máquina."
    assert html =~ "Ana desativou a conta de Bruno."
    assert html =~ "Ana reativou a conta de Bruno."
    assert html =~ "Ana tirou de um morador o cuidado da máquina."
  end

  test "pagina com 'carregar mais' quando passa da primeira página", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    # 55 atos do zelador: a primeira página (50) deixa resto.
    scope = Scope.new(zelador, tekoa)

    for i <- 1..55 do
      :ok = Maraca.record_event(scope, :quota_changed, %{"to" => i})
    end

    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Carregando mais..."

    html = render_hook(lv, "load-more")

    refute html =~ "Carregando mais..."
    assert html =~ "mudou o limite de armazenamento para"
  end

  test "Mural aparece na navegação de baixo e na lateral", %{conn: conn, morador: morador} do
    {:ok, lv, _html} = conn |> log_in(morador) |> live(~p"/mural")

    assert has_element?(lv, ".bottom-nav a[href='/mural']")
    assert has_element?(lv, ".sidebar__nav a[href='/mural']")
  end
end
