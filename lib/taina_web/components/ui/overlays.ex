defmodule TainaWeb.UI.Overlays do
  @moduledoc """
  Sobreposições do design system (Penpot, "01 - Componentes"), um `function
  component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Menu | 3fd18cd2-90f8-80f3-8008-d5c45d9b6f31 |
  | Dialog | 3fd18cd2-90f8-80f3-8008-d5c45cfb6936 |

  O `modal/confirm_dialog` viram o Dialog `dialog/1` na Wave 1. `sheet`
  (3fd18cd2-90f8-80f3-8008-d5c3d79e6789) e `actions_menu` também são da
  Wave 1. Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.Icons
  import TainaWeb.UI.Actions

  alias Phoenix.LiveView.JS

  # ---------- menu (kebab) ----------

  @doc """
  Menu suspenso acionado por botão de ícone, fechado com clique fora e Esc
  (que devolve o foco ao gatilho). O rótulo é opcional e cai no `aria-label`
  do gatilho; passe um mais específico quando o contexto ajuda (ex.: `Mais
  opções para %{name}`). Itens com `click` viram botões que disparam o
  evento/JS; itens com `navigate` viram links de navegação.

      <.menu id={"file-menu-\#{file.rkey}"} label={gettext("Mais opções para %{name}", name: file.nome)}>
        <:item icon="pencil" click={JS.push("rename", value: %{id: file.rkey})}>Renomear</:item>
        <:item icon="trash" danger click={JS.push("delete", value: %{id: file.rkey})}>Excluir</:item>
      </.menu>
  """
  attr :id, :string, required: true
  attr :icon, :string, default: "kebab"
  attr :label, :string, default: gettext("Mais opções")

  slot :item, required: true do
    attr :icon, :string
    attr :click, :any
    attr :navigate, :string, doc: "destino interno; vira <a> em vez de <button>"
    attr :danger, :boolean
  end

  def menu(assigns) do
    ~H"""
    <div
      class="menu"
      id={@id}
      phx-click-away={JS.hide(to: "##{@id}-list")}
      phx-keydown={JS.hide(to: "##{@id}-list") |> JS.focus(to: "##{@id}-trigger")}
      phx-window-keydown={JS.hide(to: "##{@id}-list")}
      phx-key="escape"
    >
      <button
        type="button"
        id={"#{@id}-trigger"}
        class="icon-btn"
        aria-label={@label}
        aria-haspopup="menu"
        aria-expanded="false"
        phx-click={
          JS.toggle(to: "##{@id}-list", display: "flex")
          |> JS.toggle_attribute({"aria-expanded", "false", "true"})
        }
      >
        <.icon name={@icon} size={20} />
      </button>
      <div id={"#{@id}-list"} class="menu__list">
        <div :for={item <- @item}>
          <.link
            :if={item[:navigate]}
            navigate={item.navigate}
            class={["menu__item", item[:danger] && "menu__item--danger"]}
            phx-click={JS.hide(to: "##{@id}-list")}
          >
            <.icon :if={item[:icon]} name={item.icon} size={18} />
            {render_slot(item)}
          </.link>
          <button
            :if={!item[:navigate]}
            type="button"
            class={["menu__item", item[:danger] && "menu__item--danger"]}
            phx-click={JS.concat(JS.hide(to: "##{@id}-list"), item[:click] || %JS{})}
          >
            <.icon :if={item[:icon]} name={item.icon} size={18} />
            {render_slot(item)}
          </button>
        </div>
      </div>
    </div>
    """
  end

  # ---------- modal ----------

  @doc """
  Modal (bottom sheet no mobile). Fecha em clique fora e Esc via `on_cancel`.
  Foco entra no diálogo quando abre; o título deve ter id `\#{@id}-title`
  (ou passe `labelledby` com o id do seu título).
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  attr :labelledby, :string,
    default: nil,
    doc: "id do título do diálogo; o padrão assume \"\#{@id}-title\""

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      :if={@show}
      id={@id}
      class="modal-overlay"
      phx-window-keydown={@on_cancel}
      phx-key="escape"
      phx-hook="ModalTrap"
    >
      <div
        class="modal"
        phx-click-away={@on_cancel}
        role="dialog"
        aria-modal="true"
        aria-labelledby={@labelledby || "#{@id}-title"}
        tabindex="-1"
      >
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Diálogo de confirmação (ações destrutivas). Reaproveita o `modal/1`.
  Título e mensagem têm os padrões da promessa da lixeira (30 dias).

      <.confirm_dialog
        id="confirm-delete"
        show={@confirm != nil}
        title={gettext("Excluir arquivo?")}
        message={gettext("Ele vai para a lixeira.")}
        on_confirm="confirm-delete"
        on_cancel={JS.push("close-modal")}
      />
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :title, :string, default: gettext("Excluir?")
  attr :message, :string, default: gettext("Vai para a lixeira. Dá para restaurar em até 30 dias.")
  attr :confirm_label, :string, default: nil
  attr :on_confirm, :any, required: true, doc: "evento (string) ou %JS{}"
  attr :on_cancel, :any, required: true

  def confirm_dialog(assigns) do
    ~H"""
    <.modal id={@id} show={@show} on_cancel={@on_cancel}>
      <h2 id={"#{@id}-title"} class="type-h3 mb-2">{@title}</h2>
      <p :if={@message} class="type-body text-secondary mb-6">{@message}</p>
      <div class="row gap-3">
        <.button variant="secondary" size="md" class="flex-1" phx-click={@on_cancel}>
          {gettext("Cancelar")}
        </.button>
        <.button variant="danger" size="md" class="flex-1" phx-click={@on_confirm}>
          {@confirm_label || gettext("Excluir")}
        </.button>
      </div>
    </.modal>
    """
  end
end
