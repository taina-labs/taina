defmodule TainaWeb.UI.Navigation do
  @moduledoc """
  Navegação do design system (Penpot, "01 - Componentes"), um `function
  component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | HubHeader | 3fd18cd2-90f8-80f3-8008-d5c3608e1697 |
  | PageHeader | 3fd18cd2-90f8-80f3-8008-d5c3b0440126 |
  | ServiceHeader | 3fd18cd2-90f8-80f3-8008-d5c4f45affe5 |
  | ServiceTabBar | 3fd18cd2-90f8-80f3-8008-d5c554eb274f |
  | Breadcrumb | 3fd18cd2-90f8-80f3-8008-d5c47a4b109d |

  Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.Icons
  import TainaWeb.UI.Content, only: [avatar: 1]

  # ---------- HubHeader ----------

  @doc """
  Cabeçalho do hub (Penpot: HubHeader, Care none/pending,
  3fd18cd2-90f8-80f3-8008-d5c3608e1697): saudação pequena, nome da comunidade
  em destaque e avatar que abre a Conta. A variante Care: pending é a
  CareLine pendurada no slot `:care` (o componente CareLine fica por conta da
  tela - composição, não herança), única indicação de "precisa de você" do
  app; nada de pontos ou badges aqui (spec 1.5).

      <.hub_header greeting="Boa noite, Ana" community="Quilombo do Café" user={@current_scope.ava} />
  """
  attr :greeting, :string, required: true, doc: "saudação completa, com o nome (ex.: Boa noite, Ana)"
  attr :community, :string, required: true, doc: "nome da comunidade (Tekoa)"
  attr :user, :any, required: true, doc: "morador (%Ava{}, lê :display_name/:username para o avatar)"
  attr :rest, :global

  slot :care, doc: "CareLine pendurada quando há pedidos esperando (Care: pending)"

  def hub_header(assigns) do
    assigns = assign(assigns, :user_name, user_display_name(assigns.user))

    ~H"""
    <header class="hub-header" {@rest}>
      <p class="hub-header__greeting">{@greeting}</p>
      <div class="hub-header__brand">
        <h1 class="hub-header__community">{@community}</h1>
        <.link navigate="/conta" class="hub-header__avatar" aria-label={gettext("Sua conta")}>
          <.avatar name={@user_name} size="sm" />
        </.link>
      </div>
      {render_slot(@care)}
    </header>
    """
  end

  defp user_display_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp user_display_name(%{username: name}) when is_binary(name), do: name
  defp user_display_name(_user), do: ""

  # ---------- back label (spec 1.5) ----------

  @doc """
  Palavra do botão de voltar das telas internas (spec 1.5): na volta para a
  raiz, "Início"; para o parente, o nome dele quando cabe em 12 caracteres,
  senão a saída honesta "Voltar".

      <.page_header title="Atas" back={~p"/documentos"} back_label={back_label(folder.name)} />
  """
  def back_label(nil), do: gettext("Início")

  def back_label(name) when is_binary(name) do
    if String.length(String.trim(name)) <= 12, do: String.trim(name), else: gettext("Voltar")
  end

  # ---------- PageHeader ----------

  @doc """
  Cabeçalho de tela interna (Penpot: PageHeader, Action none/one, Surface
  mobile/desktop, 3fd18cd2-90f8-80f3-8008-d5c3b0440126): 64 de altura, título
  sempre centrado no meio (spec 1.5), voltar (ícone + palavra) à esquerda,
  ação à direita; zonas de mesma largura mantêm o centro em qualquer rótulo.
  Substitui o antigo `Layouts.app_bar` (apagado na W2, junto com a sidebar).

      <.page_header title={gettext("Convidar")} back={~p"/moradores"} back_label={back_label(nil)}>
        <:action><.button kind="primary" navigate={...}>{gettext("Convidar")}</.button></:action>
      </.page_header>
  """
  attr :title, :string, required: true
  attr :back, :string, required: true, doc: "caminho de retorno (mesma história do back do navegador)"
  attr :back_label, :string, default: nil, doc: "palavra do back; nil vai para a regra (back_label/1)"
  attr :rest, :global

  slot :action

  def page_header(assigns) do
    ~H"""
    <header class="page-header" {@rest}>
      <div class="page-header__zone page-header__zone--start">
        <.link navigate={@back} class="page-header__back">
          <.icon name="chevron-left" size={20} />
          <span class="page-header__back-label">{@back_label || back_label(nil)}</span>
        </.link>
      </div>
      <h1 class="page-header__title">{@title}</h1>
      <div class="page-header__zone page-header__zone--end">
        {render_slot(@action)}
      </div>
    </header>
    """
  end

  # ---------- ServiceHeader ----------

  @doc """
  Cabeçalho de serviço (Penpot: ServiceHeader, Service ybira/jaci, Surface
  mobile/desktop, 3fd18cd2-90f8-80f3-8008-d5c4f45affe5): a mesma régua do
  PageHeader e, no desktop (>= 768), a fileira de abas do slot `:tabs`
  (no mobile quem mostra as abas é a `service_tab_bar` fixa no pé; spec 4.3).
  A ação "Enviar" entra no slot `:actions`.

      <.service_header service="ybira" title={gettext("Documentos")} back={~p"/"}>
        <:actions><.button kind="primary" navigate={~p"/documentos/enviar"}>{gettext("Enviar")}</.button></:actions>
        <:tabs><.service_tab_bar service="ybira" current="praca" /></:tabs>
      </.service_header>
  """
  attr :service, :string, required: true, values: ~w(ybira jaci)
  attr :title, :string, required: true
  attr :back, :string, required: true
  attr :back_label, :string, default: nil
  attr :rest, :global

  slot :actions
  slot :tabs, doc: "as abas do desktop (recomendado: <.service_tab_bar>, que troca por conta do CSS)"

  def service_header(assigns) do
    ~H"""
    <header class="service-header" {@rest}>
      <div class="service-header__top">
        <div class="service-header__zone service-header__zone--start">
          <.link navigate={@back} class="service-header__back">
            <.icon name="chevron-left" size={20} />
            <span class="service-header__back-label">{@back_label || back_label(nil)}</span>
          </.link>
        </div>
        <h1 class="service-header__title">{@title}</h1>
        <div class="service-header__zone service-header__zone--end">
          {render_slot(@actions)}
        </div>
      </div>
      <div :if={@tabs != []} class="service-header__tabs">
        {render_slot(@tabs)}
      </div>
    </header>
    """
  end

  # ---------- ServiceTabBar ----------

  # Mapa puro service -> abas (docs/web-revamp-spec.md, 4.1): rótulo, ícone e
  # destino são VARIANTE, nunca decisão de tela. Praça/Casa são o mesmo
  # FilesLive (`patch` guardian o estado); Lixeira é outra LiveView
  # (`navigate`). A tabela de rotas da W2.2 sobre nomes de caminho.
  @service_tabs %{
    "ybira" => [
      %{key: "praca", label: "Praça", icon: "praca", patch: "/documentos"},
      %{key: "casa", label: "Casa", icon: "casa", patch: "/documentos/casa"},
      %{key: "lixeira", label: "Lixeira", icon: "lixeira", navigate: "/documentos/lixeira"}
    ],
    "jaci" => [
      %{key: "grid", label: "Grade", icon: "grid", patch: "/galeria"},
      %{key: "timeline", label: "Linha do tempo", icon: "clock", patch: "/galeria/linha-do-tempo"}
    ]
  }

  @doc """
  Abas de serviço (Penpot: ServiceTabBar, Service ybira/jaci, Selected 1-3,
  3fd18cd2-90f8-80f3-8008-d5c554eb274f). As abas saem do mapa puro
  `service_tabs/1`, nunca da tela. Renderiza as DUAS formas do Penpot de uma
  vez e troca só com media query (spec 4.3): barra fixa no pé do mobile
  (`--size-nav-mobile`, safe-area) e fileira de abas sob o `service_header`
  no desktop, que o slot `:tabs` do cabeçalho recebe.

      <.service_tab_bar service="ybira" current="praca" />
  """
  attr :service, :string, required: true, values: ~w(ybira jaci)
  attr :current, :string, default: nil, doc: "key da aba corrente; recebe aria-current=page"

  def service_tab_bar(assigns) do
    assigns = assign(assigns, :tabs, service_tabs(assigns.service))

    ~H"""
    <nav class="service-tab-bar service-tab-bar--bar" aria-label={gettext("Navegação")}>
      <.link
        :for={tab <- @tabs}
        navigate={tab[:navigate]}
        patch={tab[:patch]}
        class={["service-tab-bar__item", @current == tab.key && "service-tab-bar__item--selected"]}
        aria-current={@current == tab.key && "page"}
      >
        <.icon name={tab.icon} size={20} class="service-tab-bar__icon" />
        <span class="service-tab-bar__label">{tab.label}</span>
      </.link>
    </nav>
    <nav class="service-tab-bar service-tab-bar--row" aria-label={gettext("Navegação")}>
      <.link
        :for={tab <- @tabs}
        navigate={tab[:navigate]}
        patch={tab[:patch]}
        class={["service-tab-bar__item", @current == tab.key && "service-tab-bar__item--selected"]}
        aria-current={@current == tab.key && "page"}
      >
        <.icon name={tab.icon} size={20} class="service-tab-bar__icon" />
        <span class="service-tab-bar__label">{tab.label}</span>
      </.link>
    </nav>
    """
  end

  @doc "Mapa puro de abas por serviço (testável sem socket; documentado no 4.1)."
  def service_tabs(service) when service in ~w(ybira jaci), do: Map.fetch!(@service_tabs, service)

  @doc "Chaves das abas que um serviço tem (útil para casar `current` em telas)."
  def service_tab_keys(service), do: Enum.map(service_tabs(service), & &1.key)

  # ---------- Breadcrumb ----------

  @doc """
  Caminho de migalha (Penpot: Breadcrumb, 3fd18cd2-90f8-80f3-8008-d5c47a4b109d),
  desktop only (>= 768; no mobile o word do back carrega o parente, spec 1.5
  e 4.3), separadores em chevron-right.

      <.breadcrumb>
        <:crumb label={gettext("Praça")} navigate={~p"/documentos"} />
        <:crumb label={gettext("Atas")} navigate={~p"/documentos/pasta/\#{folder.rkey}"} />
        <:crumb label={folder.name} current />
      </.breadcrumb>
  """
  attr :rest, :global

  slot :crumb, required: true do
    attr :label, :string, required: true
    attr :navigate, :string, doc: "vira <a> quando presente"
    attr :current, :boolean, doc: "elo atual (nome da pasta aberta)"
  end

  def breadcrumb(assigns) do
    ~H"""
    <nav class="breadcrumb" aria-label={gettext("Você está em")} {@rest}>
      <div :for={{crumb, index} <- Enum.with_index(@crumb, 1)} class="breadcrumb__seg">
        <.icon :if={index > 1} name="chevron-right" size={14} class="breadcrumb__sep" />
        <.link
          :if={crumb[:navigate]}
          navigate={crumb.navigate}
          class={["breadcrumb__link", crumb[:current] && "breadcrumb__current"]}
        >
          {crumb.label}
        </.link>
        <span :if={!crumb[:navigate]} class={["breadcrumb__link", crumb[:current] && "breadcrumb__current"]}>
          {crumb.label}
        </span>
      </div>
    </nav>
    """
  end
end
