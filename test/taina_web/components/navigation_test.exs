defmodule TainaWeb.UI.NavigationTest do
  @moduledoc """
  Testes de variante da navegação (Wave 1c): hub_header (greeting + comunidade
  + avatar/conta, Care opcional), a regra do rótulo de voltar (spec 1.5,
  <= 12 caracteres), page_header/service_header (título centrado no meio,
  zonas de mesma largura), service_tab_bar (mapa puro das abas por serviço,
  aria-current) e breadcrumb desktop-only.
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Content, only: [care_line: 1]
  import TainaWeb.UI.Navigation

  defp hub_header_component(assigns) do
    ~H"""
    <.hub_header greeting={@greeting} community={@community} user={@user}>
      <:care :if={@care}>
        <.care_line text="Carla pediu para abrir um arquivo da sua casa" action_label="Responder" navigate="/conta/pedidos" />
      </:care>
    </.hub_header>
    """
  end

  defp page_header_component(assigns) do
    ~H"""
    <.page_header title={@title} back={@back} back_label={@back_label}>
      <:action :if={@action}>{@action}</:action>
    </.page_header>
    """
  end

  defp service_header_component(assigns) do
    ~H"""
    <.service_header service={@service} title={@title} back={@back}>
      <:actions :if={@action}>{@action}</:actions>
      <:tabs :if={@tabs}>{@tabs}</:tabs>
    </.service_header>
    """
  end

  defp service_tab_bar_component(assigns) do
    ~H"""
    <.service_tab_bar service={@service} current={@current} />
    """
  end

  defp breadcrumb_component(assigns) do
    ~H"""
    <.breadcrumb>
      <:crumb :for={crumb <- @crumbs} label={crumb.label} navigate={crumb[:navigate]} current={crumb[:current]} />
    </.breadcrumb>
    """
  end

  defp hub_header_html(opts \\ []) do
    assigns =
      Enum.into(opts, %{
        greeting: "Boa noite, Ana",
        community: "Quilombo do Café",
        user: %{display_name: "Ana", username: "ana"},
        care: false
      })

    render_component(&hub_header_component/1, assigns)
  end

  defp page_header_html(opts \\ []) do
    assigns =
      Enum.into(opts, %{
        title: "Moradores",
        back: "/moradores",
        back_label: nil,
        action: nil
      })

    render_component(&page_header_component/1, assigns)
  end

  defp service_header_html(opts) do
    assigns =
      Enum.into(opts, %{
        service: "ybira",
        title: "Documentos",
        back: "/",
        back_label: nil,
        action: nil,
        tabs: nil
      })

    # ---------- HubHeader ----------

    render_component(&service_header_component/1, assigns)
  end

  defp tab_bar_html(opts \\ []) do
    assigns = Enum.into(opts, %{service: "ybira", current: "praca"})
    render_component(&service_tab_bar_component/1, assigns)
  end

  defp breadcrumb_html(crumbs) do
    render_component(&breadcrumb_component/1, %{crumbs: crumbs})
  end

  test "hub_header: saudação pequena, comunidade type-h1 e avatar ligando /conta" do
    html = hub_header_html()

    assert html =~ "Boa noite, Ana"
    assert html =~ ~S(class="hub-header__greeting")
    assert html =~ "Quilombo do Café"
    assert html =~ ~S(class="hub-header__community")
    assert html =~ ~S(href="/conta")
    assert html =~ ~S(aria-label="Sua conta")
    assert html =~ "A"
  end

  test "hub_header: user sem display_name cai no username no avatar" do
    # ---------- back label (spec 1.5) ----------
    html = hub_header_html(user: %{username: "carla"})

    assert html =~ "C"
  end

  test "hub_header: slot care pendura a CareLine (Care: pending)" do
    html = hub_header_html(care: true)

    assert html =~ "care-line"
    assert html =~ "Carla pediu para abrir um arquivo da sua casa"
  end

  # ---------- PageHeader ----------
  test "hub_header sem care não traz CareLine" do
    refute hub_header_html() =~ "care-line"
  end

  test "back_label: nil volta para a raiz como Início" do
    assert back_label(nil) == "Início"
  end

  test "back_label: nome do parente até 12 caracteres" do
    assert back_label("Moradores") == "Moradores"
  end

  test "back_label: nome do parente passa de 12 caracteres, word honesta Voltar" do
    assert back_label("Documentos da comarca") == "Voltar"
  end

  test "page_header: título no meio, zonas de mesma largura, back icon + palavra" do
    html = page_header_html()

    assert html =~ ~S(class="page-header")
    assert html =~ ~S(class="page-header__zone page-header__zone--start")
    assert html =~ ~S(class="page-header__zone page-header__zone--end")
    assert html =~ "Moradores"
    assert html =~ ~S(class="page-header__title")
    assert html =~ "m15 18-6-6 6-6"
    # ---------- ServiceHeader ----------
    assert html =~ ~S(class="page-header__back-label")
    assert html =~ "Início"
    assert html =~ ~S(href="/moradores")
  end

  test "page_header: back_label explcindo aparece como veio" do
    html = page_header_html(back_label: "Atas")

    assert html =~ "Atas"
    refute html =~ ">Início<"
  end

  test "page_header: ação à direita" do
    html = page_header_html(action: "Convidar")

    assert html =~ "Convidar"
  end

  test "service_header ybira: título Documentos, back e ação no slot" do
    html =
      service_header_html(service: "ybira", title: "Documentos", action: "Enviar")

    assert html =~ "Documentos"
    # ---------- ServiceTabBar ----------
    assert html =~ "service-header__title"
    assert html =~ "Enviar"
    assert html =~ "service-header__back"
    refute html =~ "service-header__tabs"
  end

  test "service_header jaci: título Galeria com as abas no slot" do
    html =
      service_header_html(
        service: "jaci",
        title: "Galeria",
        tabs: "<nav class=\"service-tab-bar\"></nav>"
      )

    assert html =~ "Galeria"
    assert html =~ "service-header__tabs"
    assert html =~ "service-tab-bar&quot;"
  end

  test "service_tab_bar ybira: Praça/Casa/Lixeira do mapa puro, aria-current na corrente" do
    html = tab_bar_html(service: "ybira", current: "praca")

    assert html =~ "Praça"
    assert html =~ "Casa"
    assert html =~ "Lixeira"
    assert html =~ ~S(aria-current="page")
    assert html =~ "data-phx-link=\"patch\""
    assert html =~ ~S(href="/documentos")
    assert html =~ ~S(href="/documentos/praca")
    assert html =~ ~S(href="/documentos/lixeira")
    # lixeira é outra LiveView: navigate em vez de patch
    assert html =~ "data-phx-link=\"redirect\""
    assert html =~ ~S(href="/documentos/lixeira")
  end

  test "service_tab_bar ybira: um único nav serve para mobile e desktop" do
    html = tab_bar_html()

    assert html =~ ~S(class="service-tab-bar")
    assert length(String.split(html, "<nav")) - 1 == 1
    assert html =~ "aria-label=\"Navegação"
  end

  test "service_tab_bar jaci: Grade/Linha do tempo, seleciona a linha do tempo" do
    html = tab_bar_html(service: "jaci", current: "timeline")

    assert html =~ "Grade"
    assert html =~ "Linha do tempo"
    assert html =~ ~S(href="/galeria/linha-do-tempo")
    # corrente: aria-current na MESMA tag do patch do key
    assert html =~ ~r|href="/galeria/linha-do-tempo"[^>]*aria-current="page"|ms
  end

  test "service_tab_bar: mapa puro por serviço, testável fora do markup" do
    # ---------- Breadcrumb ----------
    assert [%{key: "casa"}, %{key: "praca"}, %{key: "lixeira"}] = service_tabs("ybira")

    assert [%{key: "grid"}, %{key: "timeline"}] = service_tabs("jaci")
    assert service_tab_keys("ybira") == ~W(casa praca lixeira)
  end

  test "breadcrumb: elos com separador chevron-right e elo corrente" do
    crumbs = [
      %{label: "Praça", navigate: "/documentos/praca"},
      %{label: "Documentos", navigate: "/documentos"},
      %{label: "Atas", current: true}
    ]

    html = breadcrumb_html(crumbs)

    assert html =~ "Praça"
    assert html =~ "Documentos"
    assert html =~ "Atas"
    assert html =~ "breadcrumb__sep"
    assert html =~ ~S(path d="m9 18 6-6-6-6")
    assert html =~ "breadcrumb__current"
    assert html =~ ~S(aria-label)
  end
end
