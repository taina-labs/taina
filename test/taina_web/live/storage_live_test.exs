defmodule TainaWeb.StorageLiveTest do
  @moduledoc """
  Tela "Armazenamento" (docs/web-revamp-spec.md 6.4): o limite da comunidade,
  um só, vale para a caixa inteira. O card "Espaço da comunidade" leva o
  total; "O que ocupa espaço" reparte por zona (Casas, Praça, Lixeira) e a
  soma fecha com o card. Um teste por board do Penpot: `morador`, `zelador`
  (a folha do limite) e `disco inteiro`, mais o load error no componente
  puro.
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira
  alias Ypy.Maraca.Tekoa

  setup do
    tekoa = tekoa_fixture()
    %{tekoa: tekoa, admin: zelador_fixture(tekoa, %{display_name: "Ana"}), member: active_ava_fixture(tekoa)}
  end

  # board `morador`
  test "card da comunidade e repartição por zona: a soma fecha com o total", %{
    conn: conn,
    tekoa: tekoa,
    member: member
  } do
    scope = Scope.new(member, tekoa)
    {:ok, _casa} = Ybira.upload(scope, tmp_upload_fixture(String.duplicate("a", 100), "casa.txt"))
    {:ok, praca} = Ybira.upload(scope, tmp_upload_fixture(String.duplicate("b", 200), "praca.txt"))
    {:ok, _} = Ybira.publicar_file(scope, praca.rkey)

    {:ok, lv, html} = conn |> log_in(member) |> live(~p"/armazenamento")

    # o card "Espaço da comunidade" (StorageCard full)
    assert has_element?(lv, ".storage-card--full")
    assert html =~ "Espaço da comunidade"
    assert html =~ "300 B de 1,0 GB"

    # a repartição do board: casas, praça e lixeira, e a soma fecha com o card
    assert html =~ "O que ocupa espaço"
    assert html =~ "Casas (de cada morador)"
    assert html =~ "Praça"
    assert html =~ "Lixeira"
    assert html =~ "100 B"
    assert html =~ "200 B"

    # quem não cuida lê quem cuida, pelo nome; sem botão
    assert html =~ "Quem cuida da caixa escolhe quanto do disco a comunidade usa. Hoje, isso é com Ana."
    refute html =~ "Mudar limite"
  end

  # board `zelador` (a folha do limite)
  test "zelador muda o limite pela folha: rádio do disco inteiro ou GB", %{conn: conn, admin: admin} do
    {:ok, lv, html} = conn |> log_in(admin) |> live(~p"/armazenamento")

    # quem cuida não lê "isso é com quem cuida": ganha o botão
    refute html =~ "Hoje, isso é com"
    assert has_element?(lv, ~s(button[phx-click="open-quota-sheet"]), "Mudar limite")

    lv |> element(~s(button[phx-click="open-quota-sheet"])) |> render_click()

    assert has_element?(lv, "#quota-sheet")
    assert render(lv) =~ "Limite de espaço"
    assert render(lv) =~ "Fechar"
    assert render(lv) =~ "Usar o disco inteiro"
    assert render(lv) =~ "A comunidade usa todo o disco."
    assert render(lv) =~ "Definir um limite"
    assert render(lv) =~ "Limite (GB)"

    # a cota de hoje abre marcada no "Definir um limite" (1 GB do fixture)
    assert has_element?(lv, ~s(#quota-sheet input[value="limite"][checked]))
    assert has_element?(lv, ~s(#quota_gigabytes[value="1"]))

    lv |> form("#quota-form") |> render_submit(%{"quota" => %{"choice" => "limite", "gigabytes" => "10"}})

    assert render(lv) =~ "Limite atualizado."
    assert render(lv) =~ "0 B de 10 GB"
    assert render(lv) =~ "10 GB livres"
  end

  # board `disco inteiro` (o card sem limite): o número grande diz que o
  # disco inteiro está em uso, com o tamanho lido do disco, e a folga real.
  test "disco inteiro: o card diz 'Usando o disco inteiro' com o tamanho do disco", %{
    conn: conn,
    tekoa: tekoa,
    member: member
  } do
    sem_limite(tekoa)

    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/armazenamento")

    assert html =~ "Usando o disco inteiro:"
    assert html =~ "livres"
    refute html =~ "storage-card--warning"
    assert html =~ "Hoje, isso é com Ana."
  end

  # board `disco inteiro` (a folha com o rádio do disco inteiro)
  test "zelador usa o disco inteiro: a cota vira nil e o card se diz como estado", %{
    conn: conn,
    tekoa: tekoa,
    admin: admin
  } do
    sem_limite(tekoa)

    {:ok, lv, _html} = conn |> log_in(admin) |> live(~p"/armazenamento")

    lv |> element(~s(button[phx-click="open-quota-sheet"])) |> render_click()

    assert has_element?(lv, ~s(#quota-sheet input[value="inteiro"][checked]))

    lv |> form("#quota-form") |> render_submit(%{"quota" => %{"choice" => "inteiro"}})

    assert render(lv) =~ "Limite atualizado."
    assert render(lv) =~ "Usando o disco inteiro"
  end

  # load error (componente puro: o contexto não falha sob demanda)
  test "degradado: cartão de erro quando a nuvem não responde", %{conn: _conn} do
    html =
      render_component(&TainaWeb.StorageLive.storage_body/1, %{
        load_error: true,
        stats: nil,
        zones: nil,
        caretakers: [],
        zelador?: false,
        show_quota_sheet: false,
        quota_choice: nil
      })

    assert html =~ "error-card"
    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert html =~ "Falar com quem cuida"
    refute html =~ "Espaço da comunidade"
  end

  test "Armazenamento renderiza a casca page com o título no cabeçalho (a casca é quem possui o título)", %{
    conn: conn,
    member: member
  } do
    {:ok, lv, _html} = conn |> log_in(member) |> live(~p"/armazenamento")

    assert has_element?(lv, ".page-header__title", "Armazenamento")
  end

  defp sem_limite(tekoa) do
    # A cota nil = disco inteiro (spec 11.3): a escrita direta pula o contexto
    # de Tekoa (`skip_tekoa_id: true`), como no bootstrap.
    tekoa = Repo.get!(Tekoa, tekoa.id, skip_tekoa_id: true)
    {:ok, _} = Repo.update(Tekoa.changeset(tekoa, %{storage_quota_bytes: nil}), skip_tekoa_id: true)
  end
end
