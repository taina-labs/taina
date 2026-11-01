defmodule TainaWeb.Layouts do
  @moduledoc """
  Cascas de página (spec 5, docs/web-revamp-spec.md): `root/1` o documento
  HTML; `hub/1` (hub `/`), `service/1` (Documentos, Galeria), `page/1` (cívicas
  e detalhes empurrados), `auth/1` (fundo sólido `--bg-deep`) e `viewer/1`
  (fullscreen). A casca possui o cabeçalho e o próprio título: nenhuma tela
  renderiza `<h1>` de título nem barra própria (spec 1.5).

  No Penpot ("Cofre da Comunidade - UI v1") a referência são as páginas
  `02 - Mobile` e `03 - Web` e os quadros `Frame / Web movel`
  (cc1037dc-e8ab-80cc-8008-d5c4625371e0), `Frame / Desktop`
  (cc1037dc-e8ab-80cc-8008-d5c46431f4fd) e `Frame / iOS`
  (cc1037dc-e8ab-80cc-8008-d5c4608aa144) - os boards de tela por cima deles é
  que mostram o conteúdo de cada casca.

  LiveViews envolvem o próprio conteúdo explicitamente:

      <Layouts.service service="ybira" current="praca" ...>
  """

  use TainaWeb, :html

  embed_templates "layouts/*"

  @doc """
  Shell do hub (`/`): flash, pular-para-conteúdo e `main` com conteúdo limitado
  a `--measure-wide`. Sem barra de cabeçalho: o `hub_header` é conteúdo da
  tela; sem abas (spec 1.4/1.5).

      <Layouts.hub flash={@flash}>
        <.hub_header ... />
        ...
      </Layouts.hub>
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def hub(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <a class="skip-link" href="#main-content">{gettext("Pular para o conteúdo")}</a>
    <main class="shell shell--hub" id="main-content">
      <div class="shell__content">{render_slot(@inner_block)}</div>
    </main>
    """
  end

  @doc """
  Shell de serviço (Documentos, Galeria): `service_header` com o `service_tab_bar`
  no slot `:tabs` - o componente renderiza as DUAS formas (barra fixa no pé do
  mobile, fileira no desktop) e o CSS troca sozinho em 768 (spec 4.3); a barra
  entra UMA vez aqui, nunca na tela. Conteúdo limitado a `--measure-shell`,
  FAB opcional (slots) fixado pelo próprio CSS.

      <Layouts.service flash={@flash} service="ybira" current="praca"
        title={gettext("Documentos")} back={~p"/"}>
        <:actions><.button ... /></:actions>
        <:fab><.fab navigate={~p"/documentos/enviar"} /></:fab>
        conteúdo
      </Layouts.service>
  """
  attr :flash, :map, required: true
  attr :service, :string, required: true, values: ~w(ybira jaci)
  attr :current, :string, required: true, doc: "key da aba corrente, do service_tab_bar"
  attr :title, :string, required: true
  attr :back, :string, required: true, doc: "caminho de retorno (mesma história do back do navegador)"
  attr :back_label, :string, default: nil
  slot :actions, doc: "ações do cabeçalho (ex: botão Enviar)"
  slot :fab, doc: "FAB mobile; o CSS o esconde no desktop"
  slot :inner_block, required: true

  def service(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <a class="skip-link" href="#main-content">{gettext("Pular para o conteúdo")}</a>
    <div class="shell shell--service">
      <.service_header service={@service} title={@title} back={@back} back_label={@back_label}>
        <:actions>{render_slot(@actions)}</:actions>
        <:tabs><.service_tab_bar service={@service} current={@current} /></:tabs>
      </.service_header>
      <main class="shell__content" id="main-content">
        {render_slot(@inner_block)}
        {render_slot(@fab)}
      </main>
    </div>
    """
  end

  @doc """
  Shell de página (cívicas, detalhes empurrados): `page_header` sticky (título
  centrado, back à esquerda, ação à direita) e conteúdo limitado a
  `--measure-shell`. Sem abas (spec 1.5).

      <Layouts.page flash={@flash} title={gettext("Mural")} back={~p"/"}>
        <:action><.icon_button ... /></:action>
        conteúdo
      </Layouts.page>
  """
  attr :flash, :map, required: true
  attr :title, :string, required: true
  attr :back, :string, required: true
  attr :back_label, :string, default: nil
  slot :action, doc: "ação única do cabeçalho (spec 1.5)"
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <a class="skip-link" href="#main-content">{gettext("Pular para o conteúdo")}</a>
    <div class="shell shell--page">
      <.page_header title={@title} back={@back} back_label={@back_label}>
        <:action>{render_slot(@action)}</:action>
      </.page_header>
      <main class="shell__content" id="main-content">{render_slot(@inner_block)}</main>
    </div>
    """
  end

  @doc """
  Shell de auth (setup, login, convite, redefinir): fundo sólido `--bg-deep`
  (sem céu, sem estrelas, sem horizonte - spec 6.5), conteúdo limitado a
  `--measure-card` e, do tablet para cima, o cartão do board (superfície
  elevada, hairline, `--radius-lg`). O ConnectionNotice não mora aqui: cada
  tela o coloca abaixo do próprio cabeçalho, como nos boards ("sem https" em
  `02 - Mobile`), e o `secure_connection?` vem de `Hooks.on_mount(:connection)`.

      <Layouts.auth flash={@flash}>
        ...
      </Layouts.auth>
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <main class="shell shell--auth">
      <div class="shell__content">{render_slot(@inner_block)}</div>
    </main>
    """
  end

  @doc """
  Shell do visualizador (`/galeria/:id`): tela cheia, sem cabeçalho, sem abas,
  sem pular-para-conteúdo (o conteúdo é o foco único do visualizador, spec 5).

      <Layouts.viewer flash={@flash}>
        <.viewer ... />
      </Layouts.viewer>
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def viewer(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <main class="shell shell--viewer">
      {render_slot(@inner_block)}
    </main>
    """
  end
end
