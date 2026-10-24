defmodule TainaWeb.Layouts do
  @moduledoc """
  Cascas de página. `root` é o documento HTML; as novas (spec 5,
  docs/web-revamp-spec.md): `hub/1`, `service/1`, `page/1`, `auth/1`
  (fundo sólido `--bg-deep`) e `viewer/1`. Ainda o shell velho `app/1`
  (bottom-nav mobile, sidebar desktop) e `auth_legacy/1` (céu noturno),
  que a próxima onda re-entrelaça e apaga.

  LiveViews envolvem o próprio conteúdo explicitamente:

      <Layouts.app current_scope={@current_scope} active_tab={:files} ...>
  """

  use TainaWeb, :html

  embed_templates "layouts/*"

  # ---------- cascas novas do revamp (W2a, docs/web-revamp-spec.md, secao 5) ----------
  # Puramente aditivo: nenhuma tela usa essas cascas ainda. A proxima onda troca
  # `app`/`app_bar` (e o cepo `:shell` do Hooks) pelas cinco funcoes deste bloco.

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
      <main class="shell__content" id="main-content">{render_slot(@inner_block)}</main>
      {render_slot(@fab)}
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
  (sem céu, sem estrelas, sem horizonte - spec 6.5) e cartão limitado a
  `--measure-card`. `secure_connection?` chega por `Hooks.on_mount(:connection)`;
  quando a página abriu fora da rede da comunidade (http, sem loopback), o
  ConnectionNotice entra acima do cartão.

      <Layouts.auth flash={@flash}>
        ...
      </Layouts.auth>
  """
  attr :flash, :map, required: true

  attr :secure_connection?,
       :boolean,
       doc: "atribuído por Hooks.on_mount(:connection); o Map.put_new abaixo cobre o render sem ele"

  slot :inner_block, required: true

  def auth(assigns) do
    assigns = Map.put_new(assigns, :secure_connection?, true)

    ~H"""
    <.flash_group flash={@flash} />
    <main class="shell shell--auth">
      <.connection_notice :if={@secure_connection? == false} />
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

  @doc """
  Shell autenticado. `active_tab` marca o item ativo na navegação
  (`:home`, `:files`, `:photos`, `:members`, `:mural`, `:saude`, `:account`).
  `storage_stats` (opcional) alimenta o mini-card de armazenamento da sidebar.
  `account_alert` acende um ponto na aba Conta quando há pedido esperando.
  """
  attr :flash, :map, required: true
  attr :current_scope, Ypy.Scope, default: nil
  attr :active_tab, :atom, default: nil
  # A sidebar (desktop) acende pela aba "de verdade" da tela; a bottom-nav
  # (mobile) não tem slot para toda aba, então telas sem slot próprio (ex:
  # Moradores) passam `mobile_active_tab` para acender a aba mais próxima.
  attr :mobile_active_tab, :atom,
    default: nil,
    doc: "aba do bottom-nav mobile quando difere de active_tab; vale mobile_active_tab || active_tab"

  attr :storage_stats, :map, default: nil, doc: "%{used_bytes: _, quota_bytes: _}"
  attr :account_alert, :boolean, default: false, doc: "ponto na aba Conta quando há pedido esperando"
  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :mobile_tab, assigns[:mobile_active_tab] || assigns.active_tab)

    ~H"""
    <.flash_group flash={@flash} />
    <div id="app-shell" class="shell">
      <a class="skip-link" href="#main-content">{gettext("Pular para o conteúdo")}</a>
      <aside class="sidebar">
        <.link navigate={~p"/"} class="sidebar__logo">
          <.icon name="spark" size={22} /> Tainá
        </.link>
        <nav class="sidebar__nav" aria-label={gettext("Navegação")}>
          <.sidebar_item navigate={~p"/"} icon="home" active={@active_tab == :home} label={gettext("Início")} />
          <.sidebar_item
            navigate={~p"/documentos"}
            icon="folder"
            active={@active_tab == :files}
            label={gettext("Arquivos")}
          />
          <.sidebar_item navigate={~p"/galeria"} icon="image" active={@active_tab == :photos} label={gettext("Fotos")} />
          <.sidebar_item
            navigate={~p"/moradores"}
            icon="user"
            active={@active_tab == :members}
            label={gettext("Moradores")}
          />
          <.sidebar_item
            navigate={~p"/mural"}
            icon="mural"
            active={@active_tab == :mural}
            label={gettext("Mural")}
          />
          <.sidebar_item
            navigate={~p"/saude"}
            icon="saude"
            active={@active_tab == :saude}
            label={gettext("Saúde")}
          />
          <.sidebar_item
            navigate={~p"/conta"}
            icon="shield"
            active={@active_tab == :account}
            alert={@account_alert}
            label={gettext("Conta")}
          />
        </nav>
        <.card :if={@storage_stats} raised class="mt-4">
          <p class="type-caption text-muted mb-2">{gettext("Armazenamento")}</p>
          <.progress value={storage_percent(@storage_stats)} />
          <p class="type-caption text-muted mt-2">
            {format_bytes(@storage_stats.used_bytes)} de {format_bytes(@storage_stats.quota_bytes)}
          </p>
          <p class="type-caption text-success mt-1">
            {format_bytes(max(@storage_stats.quota_bytes - @storage_stats.used_bytes, 0))} {gettext("livres")}
          </p>
        </.card>
      </aside>

      <div class="shell__main">
        <main class="shell__content" id="main-content">
          {render_slot(@inner_block)}
        </main>
      </div>

      <nav class="bottom-nav" aria-label={gettext("Navegação")}>
        <.bottom_nav_item navigate={~p"/"} icon="home" active={@mobile_tab == :home} label={gettext("Início")} />
        <.bottom_nav_item
          navigate={~p"/documentos"}
          icon="folder"
          active={@mobile_tab == :files}
          label={gettext("Arquivos")}
        />
        <.bottom_nav_item navigate={~p"/galeria"} icon="image" active={@mobile_tab == :photos} label={gettext("Fotos")} />
        <.bottom_nav_item
          navigate={~p"/mural"}
          icon="mural"
          active={@mobile_tab == :mural}
          label={gettext("Mural")}
        />
        <.bottom_nav_item
          navigate={~p"/saude"}
          icon="saude"
          active={@mobile_tab == :saude}
          label={gettext("Saúde")}
        />
        <.bottom_nav_item
          navigate={~p"/conta"}
          icon="shield"
          active={@mobile_tab == :account}
          alert={@account_alert}
          label={gettext("Conta")}
        />
      </nav>
    </div>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :alert, :boolean, default: false

  defp sidebar_item(assigns) do
    ~H"""
    <.link navigate={@navigate} class="sidebar__item" aria-current={@active && "page"} aria-label={nav_label(@label, @alert)}>
      <.icon name={@icon} size={20} /> {@label}
      <span :if={@alert} class="nav-dot" aria-hidden="true"></span>
    </.link>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  attr :alert, :boolean, default: false

  defp bottom_nav_item(assigns) do
    ~H"""
    <.link navigate={@navigate} class="bottom-nav__item" aria-current={@active && "page"} aria-label={nav_label(@label, @alert)}>
      <.icon name={@icon} size={22} />
      <span class="bottom-nav__label">{@label}</span>
      <span :if={@alert} class="nav-dot" aria-hidden="true"></span>
    </.link>
    """
  end

  # Sufixo no rótulo acessível só quando o ponto acende: o leitor de tela anuncia
  # "Conta, há pedidos esperando". Sem ponto, o rótulo fica como está.
  defp nav_label(label, true), do: label <> ", " <> gettext("há pedidos esperando")
  defp nav_label(label, false), do: label

  defp storage_percent(%{used_bytes: used, quota_bytes: quota})
       when is_integer(used) and is_integer(quota) and quota > 0 do
    (used / quota * 100) |> round() |> min(100) |> max(0)
  end

  defp storage_percent(_stats), do: 0

  @doc """
  Layout das telas públicas (setup, login, convite): céu noturno, estrelas e
  horizonte aquecido. Marginalizado pela casca `auth/1` nova em cima (mesmo
  nome, um só `def` possível, especificação 5): as telas de auth renderizam a
  casca nova desde a W2a e quaisquer LifeViews são re-entrelaçadas na W2b,
  que apaga esta.
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def auth_legacy(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <div class="auth-layout">
      <main class="auth-layout__card">
        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  @doc """
  Barra superior de telas internas mobile: voltar, título centrado e ação.
  """
  attr :title, :string, required: true
  attr :back, :string, required: true
  slot :action

  def app_bar(assigns) do
    ~H"""
    <header class="appbar">
      <.icon_button name="chevron-left" label={gettext("Voltar")} navigate={@back} />
      <h1 class="appbar__title">{@title}</h1>
      <div :if={@action != []} class="row gap-1">{render_slot(@action)}</div>
      <span :if={@action == []} class="appbar__spacer"></span>
    </header>
    """
  end
end
