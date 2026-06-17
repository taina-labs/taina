defmodule TainaWeb.Layouts do
  @moduledoc """
  Cascas de página. `root` é o documento HTML; `app/1` é o shell autenticado
  (bottom-nav no mobile, sidebar no desktop, telas "02/03" do Penpot); e
  `auth/1` é o céu noturno com horizonte das telas de setup/login/convite.

  LiveViews envolvem o próprio conteúdo explicitamente:

      <Layouts.app current_scope={@current_scope} active_tab={:files} ...>
  """

  use TainaWeb, :html

  embed_templates "layouts/*"

  @doc """
  Shell autenticado. `active_tab` marca o item ativo na navegação
  (`:home`, `:files`, `:photos`, `:members`, `:account`).
  `storage_stats` (opcional) alimenta o mini-card de armazenamento da sidebar.
  """
  attr :flash, :map, required: true
  attr :current_scope, Taina.Scope, default: nil
  attr :active_tab, :atom, default: nil
  attr :storage_stats, :map, default: nil, doc: "%{used_bytes: _, quota_bytes: _}"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <div class="shell">
      <aside class="sidebar">
        <.link navigate={~p"/"} class="sidebar__logo">
          <.icon name="spark" size={22} /> Tainá
        </.link>
        <nav class="sidebar__nav">
          <.sidebar_item navigate={~p"/"} icon="home" active={@active_tab == :home} label={gettext("Início")} />
          <.sidebar_item
            navigate={~p"/arquivos"}
            icon="folder"
            active={@active_tab == :files}
            label={gettext("Arquivos")}
          />
          <.sidebar_item navigate={~p"/fotos"} icon="image" active={@active_tab == :photos} label={gettext("Fotos")} />
          <.sidebar_item
            navigate={~p"/membros"}
            icon="user"
            active={@active_tab == :members}
            label={gettext("Membros")}
          />
          <.sidebar_item
            navigate={~p"/conta"}
            icon="shield"
            active={@active_tab == :account}
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
        <main class="shell__content">
          {render_slot(@inner_block)}
        </main>
      </div>

      <nav class="bottom-nav">
        <.bottom_nav_item navigate={~p"/"} icon="home" active={@active_tab == :home} label={gettext("Início")} />
        <.bottom_nav_item
          navigate={~p"/arquivos"}
          icon="folder"
          active={@active_tab == :files}
          label={gettext("Arquivos")}
        />
        <.bottom_nav_item navigate={~p"/fotos"} icon="image" active={@active_tab == :photos} label={gettext("Fotos")} />
        <.bottom_nav_item
          navigate={~p"/conta"}
          icon="user"
          active={@active_tab in [:account, :members]}
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

  defp sidebar_item(assigns) do
    ~H"""
    <.link navigate={@navigate} class="sidebar__item" aria-current={@active && "page"}>
      <.icon name={@icon} size={20} /> {@label}
    </.link>
    """
  end

  attr :navigate, :string, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false

  defp bottom_nav_item(assigns) do
    ~H"""
    <.link navigate={@navigate} class="bottom-nav__item" aria-current={@active && "page"}>
      <.icon name={@icon} size={22} />
      <span>{@label}</span>
    </.link>
    """
  end

  defp storage_percent(%{used_bytes: used, quota_bytes: quota})
       when is_integer(used) and is_integer(quota) and quota > 0 do
    (used / quota * 100) |> round() |> min(100) |> max(0)
  end

  defp storage_percent(_stats), do: 0

  @doc """
  Layout das telas públicas (setup, login, convite): céu noturno, estrelas e
  horizonte aquecido.
  """
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <.flash_group flash={@flash} />
    <div class="auth-layout">
      <div class="auth-layout__card">
        {render_slot(@inner_block)}
      </div>
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
