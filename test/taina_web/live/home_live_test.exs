defmodule TainaWeb.HomeLiveTest do
  @moduledoc """
  O hub (`/`, docs/web-revamp-spec.md 6.1): cabeçalho, CareLine com pedido,
  Serviços, Da comunidade com meta viva, Espaço da comunidade e Recentes.
  Cobre os quatro estados dos boards: padrão, com pedido, recentes vazio e
  degradado (este último no componente puro do corpo, já que as chamadas de
  contexto não falham de propósito no teste).
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira
  alias TainaWeb.HomeLive

  test "sem sessão, redireciona para o login", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/")
  end

  test "padrão: cabeçalho, serviços, comunidade, espaço e recentes", %{conn: conn} do
    tekoa = tekoa_fixture(%{name: "Quilombo do Café"})
    ana = zelador_fixture(tekoa, %{display_name: "Ana"})
    active_ava_fixture(tekoa, %{display_name: "Bruno"})
    {:ok, _invite} = Maraca.invite_user(ana, tekoa)
    {:ok, file} = Ybira.upload(Scope.new(ana, tekoa), tmp_upload_fixture("oi", "ata.txt"))

    {:ok, lv, html} = conn |> log_in(ana) |> live(~p"/")

    # HubHeader: saudação com o nome da pessoa, comunidade em destaque e avatar.
    assert has_element?(lv, ".hub-header")
    assert lv |> element(".hub-header__greeting") |> render() =~ ", Ana"
    assert has_element?(lv, ".hub-header__community", "Quilombo do Café")
    assert has_element?(lv, ~s(.hub-header a[aria-label="Sua conta"]))

    # Serviços: dois cartões, os mesmos do board.
    assert has_element?(lv, ".service-card", "Documentos")
    assert has_element?(lv, ".service-card", "Galeria")
    assert html =~ "Arquivos da casa e da praça"
    assert html =~ "Fotos da casa e da praça"

    # Sem pedido, a linha de cuidado não existe.
    refute has_element?(lv, ".care-line")

    # Da comunidade: as três linhas cívicas com meta viva.
    assert has_element?(lv, ".list-row--civic", "Mural")
    assert html =~ "Ana guardou um arquivo na caixa, hoje"
    assert has_element?(lv, ".list-row--civic", "Saúde da comunidade")
    assert has_element?(lv, ".list-row--civic", "Moradores")
    assert html =~ "2 pessoas na comunidade"

    # Espaço da comunidade no cartão compacto, com o destino dos detalhes.
    assert has_element?(lv, ".storage-card", "Espaço da comunidade")
    assert has_element?(lv, ~s(.storage-card a[href="/armazenamento"]))
    assert has_element?(lv, ".storage-card__meta", "de 1,0 GB usados")

    # Recentes: metadados separados por vírgula, sem a zona no meio.
    assert has_element?(lv, ".list-row--file", "ata.txt")
    assert html =~ "Texto, 2 B, hoje"
    assert has_element?(lv, ~s(a[href="/documentos/#{file.rkey}"]))
  end

  test "com pedido: CareLine no topo do hub, apontando para os pedidos", %{conn: conn} do
    tekoa = tekoa_fixture()
    ana = active_ava_fixture(tekoa, %{display_name: "Ana"})
    carla = active_ava_fixture(tekoa, %{display_name: "Carla"})
    {:ok, file} = Ybira.upload(Scope.new(ana, tekoa), tmp_upload_fixture("oi", "carta.txt"))
    {:ok, _pedido} = Maraca.pedir_acesso(Scope.new(carla, tekoa), "ypy.file.v0", file.rkey, "Preciso ler")

    {:ok, lv, _html} = conn |> log_in(ana) |> live(~p"/")

    assert has_element?(lv, ".care-line", "Carla pediu para abrir um arquivo da sua casa")
    assert has_element?(lv, ".care-line", "Responder")
    assert has_element?(lv, ~s(.care-line[href="/conta/pedidos"]))
  end

  test "recentes vazio: estado honesto, sem chamada para agir", %{conn: conn} do
    tekoa = tekoa_fixture()
    ana = active_ava_fixture(tekoa, %{display_name: "Ana"})

    {:ok, lv, html} = conn |> log_in(ana) |> live(~p"/")

    assert has_element?(lv, ".empty-state", "Nada recente")
    assert html =~ "O que chegar de novo aparece aqui."
    refute html =~ "Enviar arquivos"
    refute has_element?(lv, ".list-row--file")

    # O resto do hub continua vivo acima.
    assert has_element?(lv, ".service-card", "Documentos")
    assert has_element?(lv, ".storage-card")
  end

  test "recentes para em quatro itens", %{conn: conn} do
    tekoa = tekoa_fixture()
    ana = active_ava_fixture(tekoa, %{display_name: "Ana"})
    scope = Scope.new(ana, tekoa)

    for n <- 1..5 do
      {:ok, _file} = Ybira.upload(scope, tmp_upload_fixture("oi", "arquivo-#{n}.txt"))
    end

    {:ok, _lv, html} = conn |> log_in(ana) |> live(~p"/")

    assert length(Regex.scan(~r/list-row--file/, html)) == 4
  end

  test "degradado: cartão de erro no topo e seções viram esqueleto", %{conn: _conn} do
    tekoa = tekoa_fixture(%{name: "Quilombo do Café"})
    ana = active_ava_fixture(tekoa, %{display_name: "Ana"})

    hub = %{
      care: {:ok, nil},
      community: {:error, :timeout},
      storage: {:error, :timeout},
      recent: {:error, :timeout}
    }

    html = render_component(&HomeLive.hub_body/1, %{hub: hub, scope: Scope.new(ana, tekoa)})

    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert html =~ "Tentar de novo"
    assert html =~ "Falar com quem cuida"

    # As seções que dependem da nuvem esqueletam, não somem.
    assert html =~ "list-row"
    assert html =~ "skeleton"
    refute html =~ "Nada recente"

    # O que não depende da nuvem continua no ar: o morador ainda sabe ir para
    # Documentos e Galeria.
    assert html =~ "Documentos"
    assert html =~ "Galeria"
  end

  test "degradado parcial: só a seção que falhou esqueleta", %{conn: _conn} do
    tekoa = tekoa_fixture()
    ana = active_ava_fixture(tekoa, %{display_name: "Ana"})
    {:ok, file} = Ybira.upload(Scope.new(ana, tekoa), tmp_upload_fixture("oi", "ata.txt"))

    hub = %{
      care: {:ok, "Carla pediu para abrir um arquivo da sua casa"},
      community: {:ok, [community_row("Mural")]},
      storage: {:ok, %{used_bytes: 1024, quota_bytes: 1024 * 1024}},
      recent: {:error, :timeout}
    }

    html = render_component(&HomeLive.hub_body/1, %{hub: hub, scope: Scope.new(ana, tekoa)})

    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert html =~ "Carla pediu para abrir um arquivo da sua casa"
    assert html =~ "Mural"
    assert html =~ "1,0 KB de 1,0 MB usados"
    refute html =~ "Nada recente"
    refute html =~ file.nome
  end

  defp community_row(title) do
    %{mark: "mural", title: title, meta: "hoje", path: "/mural"}
  end
end
