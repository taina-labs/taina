defmodule TainaWeb.MuralLiveTest do
  @moduledoc """
  Tela do mural: frases simples de quem fez o quê, agrupadas por dia,
  somente leitura para todos os papéis (zelador incluso).
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

  test "atos do dia a dia viram frases com quem fez e quando", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    scope = Scope.new(zelador, tekoa)
    path = tmp_upload_fixture("conteúdo", "estatuto.pdf")
    {:ok, file} = Ybira.upload(scope, path, filename: "estatuto.pdf")
    {:ok, _file} = Ybira.publicar_file(scope, file.public_id)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Ana publicou o arquivo &quot;estatuto.pdf&quot; na praça."
    assert html =~ "hoje"
  end

  test "pedido de acesso vira frase com quem pediu e de quem", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador,
    morador: morador
  } do
    owner_scope = Scope.new(zelador, tekoa)
    path = tmp_upload_fixture("segredo", "diario.txt")
    {:ok, file} = Ybira.upload(owner_scope, path, filename: "diario.txt")
    {:ok, _request} = Maraca.request_access(morador, zelador, "ybira_file", file.public_id, "quero ler")

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Bruno pediu acesso à casa de Ana."
  end

  test "zelador vê o mesmo mural, sem controle nenhum sobre o registro", %{conn: conn, tekoa: tekoa, zelador: zelador} do
    :ok = Maraca.record_event(tekoa.public_id, zelador.id, :invite_created, %{"role" => "morador"})

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
    assert {:ok, invited} = Maraca.invite_user(zelador, tekoa, role: :zelador)

    assert {:ok, _accepted} =
             Maraca.accept_invite(invited.invite_token, %{
               "username" => "joana",
               "display_name" => "Joana",
               "password" => "senhasegura123",
               "password_confirmation" => "senhasegura123"
             })

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/mural")

    assert html =~ "Joana entrou na comunidade para cuidar da máquina."
  end

  test "aceite antigo (sem papel no registro) continua com a frase genérica", %{
    conn: conn,
    tekoa: tekoa,
    morador: morador
  } do
    :ok = Maraca.record_event(tekoa.public_id, morador.id, :invite_accepted, %{})

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
    assert {:ok, _ava} = Maraca.mint_reset_link(scope, morador)

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

    # ganhou o papel, e depois voltou a ser morador
    assert html =~ "Ana deu a Bruno o cuidado da máquina."
    assert html =~ "Ana tirou de Bruno o cuidado da máquina."
    assert html =~ "Ana reativou a conta de Bruno."
  end

  test "pagina com 'carregar mais' quando passa da primeira página", %{conn: conn, tekoa: tekoa, morador: morador} do
    # 55 atos do sistema: a primeira página (50) deixa resto.
    for i <- 1..55 do
      :ok = Maraca.record_event(tekoa.public_id, nil, :quota_changed, %{"to" => i})
    end

    {:ok, lv, html} = conn |> log_in(morador) |> live(~p"/mural")

    assert html =~ "Carregando mais..."

    html = render_hook(lv, "load-more")

    refute html =~ "Carregando mais..."
    assert html =~ "O sistema mudou o limite de armazenamento para"
  end

  test "Mural aparece na navegação de baixo e na lateral", %{conn: conn, morador: morador} do
    {:ok, lv, _html} = conn |> log_in(morador) |> live(~p"/mural")

    assert has_element?(lv, ".bottom-nav a[href='/mural']")
    assert has_element?(lv, ".sidebar__nav a[href='/mural']")
  end
end
