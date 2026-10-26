defmodule TainaWeb.UI.Overlays do
  @moduledoc """
  Sobreposições do design system (Penpot, "01 - Componentes"), um `function
  component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Sheet | 3fd18cd2-90f8-80f3-8008-d5c3d79e6789 |
  | Dialog | 3fd18cd2-90f8-80f3-8008-d5c45cfb6936 |
  | Menu | 3fd18cd2-90f8-80f3-8008-d5c45d9b6f31 |
  | ActionsMenu (composição Sheet + Menu) | sem componente próprio |
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
  evento/JS; itens com `navigate` viram links de navegação. O ícone fica
  sempre à esquerda (spec 10: dívida do board resolvida no código).

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
        class="icon-button"
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

  # ---------- sheet ----------

  @doc """
  Bottom sheet mobile (Penpot: Sheet, Kind actions/content,
  3fd18cd2-90f8-80f3-8008-d5c3d79e6789): painel que sobe por cima do
  conteúdo, com puxador, título, "Fechar" visível e fechamento por Esc e
  clique fora (`on_cancel`). Foco circula só dentro do painel (`ModalTrap`).

    * `kind="actions"`: lista de ações no slot `:item` (`icon`, `click`,
      `navigate`, `danger`) - dívida do board resolvida no código: ícone
      sempre à esquerda (spec 10), "Remover" vermelho com `danger`.
    * `kind="content"`: corpo livre no `:inner_block` + ação única (`Entendi`)
      no slot `:action` - a W3.2 passa o `<.button>` da própria tela.

  A variante Zone casa/praca do Penpot é o CONTEÚDO dos itens (qual ação de
  zona aparece primeiro), decisão da tela: o componente não tem attrs de zona.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false

  attr :on_cancel, :any,
    required: true,
    doc: "evento (string) ou %JS{} de fechamento; Esc, clique fora e Fechar"

  attr :title, :string, default: nil
  attr :kind, :string, default: "actions", values: ~w(actions content)

  slot :item, doc: "linha de ação do Kind actions" do
    attr :icon, :string
    attr :click, :any
    attr :navigate, :string, doc: "vira <a> em vez de <button>"
    attr :danger, :boolean, doc: "linha de destruição (Remover), vermelha"
  end

  slot :action, doc: "ação única do Kind content (ex.: o botão Entendi)"
  slot :inner_block, doc: "corpo do Kind content"

  def sheet(%{kind: "content"} = assigns) do
    ~H"""
    <div
      :if={@show}
      id={@id}
      class="sheet"
      phx-hook="ModalTrap"
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div
        class="sheet__panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        tabindex="-1"
        phx-click-away={@on_cancel}
      >
        <span class="sheet__grabber" aria-hidden="true"></span>
        <header class="sheet__head">
          <h2 :if={@title} id={"#{@id}-title"} class="sheet__title">{@title}</h2>
          <button type="button" class="sheet__close" phx-click={@on_cancel}>
            {gettext("Fechar")}
          </button>
        </header>
        <div class="sheet__body">
          {render_slot(@inner_block)}
        </div>
        <div :if={@action != []} class="sheet__foot">
          {render_slot(@action)}
        </div>
      </div>
    </div>
    """
  end

  def sheet(assigns) do
    assigns = assign(assigns, :cancel_js, cancel_js(assigns[:on_cancel]))

    ~H"""
    <div
      :if={@show}
      id={@id}
      class="sheet"
      phx-hook="ModalTrap"
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div
        class="sheet__panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={"#{@id}-title"}
        tabindex="-1"
        phx-click-away={@on_cancel}
      >
        <span class="sheet__grabber" aria-hidden="true"></span>
        <header class="sheet__head">
          <h2 :if={@title} id={"#{@id}-title"} class="sheet__title">{@title}</h2>
          <button type="button" class="sheet__close" phx-click={@on_cancel}>
            {gettext("Fechar")}
          </button>
        </header>
        <div class="sheet__items">
          <div :for={item <- @item}>
            <.link
              :if={item[:navigate]}
              navigate={item.navigate}
              class={["sheet__item", item[:danger] && "sheet__item--danger"]}
              phx-click={@on_cancel}
            >
              <.icon :if={item[:icon]} name={item.icon} size={20} />
              <span class="sheet__item-label">{render_slot(item)}</span>
            </.link>
            <button
              :if={!item[:navigate]}
              type="button"
              class={["sheet__item", item[:danger] && "sheet__item--danger"]}
              phx-click={JS.concat(@cancel_js, item[:click] || %JS{})}
            >
              <.icon :if={item[:icon]} name={item.icon} size={20} />
              <span class="sheet__item-label">{render_slot(item)}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # on_cancel chega como evento (string) ou %JS{}; para concatenar com o
  # click do item precisa de %JS{}.
  defp cancel_js(js) when is_struct(js, JS), do: js
  defp cancel_js(event) when is_binary(event), do: JS.push(event)
  defp cancel_js(_nil), do: %JS{}

  # ---------- dialog ----------

  @doc """
  Diálogo (Penpot: Dialog, Kind confirm/destructive,
  3fd18cd2-90f8-80f3-8008-d5c45cfb6936): confirmação e destruição. O botão
  seguro ("Cancelar"/"Deixar na casa") é sempre
  secundário; a ação confirmatória é `kind="primary"` no confirm e
  `kind="danger"` no destructive. Fecha em Esc sempre; clique fora fecha
  apenas no confirm (no destructive a mão da pessoa tem que tocar um botão).

      <.dialog
        id="confirm-publish"
        show={@confirm != nil}
        kind="confirm"
        title={gettext("Publicar na praça?")}
        body={gettext("Todos os moradores vão poder ver e baixar este arquivo. Você pode voltar para a casa depois.")}
        cancel_label={gettext("Deixar na casa")}
        confirm_label={gettext("Publicar")}
        on_confirm={JS.push("confirm-zona")}
        on_cancel={JS.push("close-zona")}
      />
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :kind, :string, default: "confirm", values: ~w(confirm destructive)
  attr :title, :string, default: nil
  attr :body, :string, default: nil
  attr :confirm_label, :string, default: nil
  attr :cancel_label, :string, default: gettext("Cancelar")
  attr :on_confirm, :any, default: nil, doc: "evento (string) ou %JS{}; presença desenha o rodapé"
  attr :on_cancel, :any, default: %JS{}, doc: "evento (string) ou %JS{} de fechamento"
  attr :labelledby, :string, default: nil, doc: "id do título; padrão \"\#{@id}-title\""

  slot :inner_block, doc: "conteúdo livre no lugar de title/body (ex.: formulário montado pela tela)"

  def dialog(assigns) do
    confirms? = assigns[:on_confirm] not in [nil, false]
    destructive? = assigns[:kind] == "destructive"

    assigns =
      assigns
      |> assign(:confirm_label, assigns[:confirm_label] || dialog_confirm_label(destructive?))
      |> assign(:cancel_label, assigns[:cancel_label] || gettext("Cancelar"))
      |> assign(:labelledby, assigns[:labelledby] || "#{assigns.id}-title")
      # clique fora fecha no confirm; destructive espera um botão (1.7)
      |> assign(:on_away, if(destructive?, do: nil, else: assigns[:on_cancel] || %JS{}))
      |> assign(:confirm_kind, if(destructive?, do: "danger", else: "primary"))
      |> assign(:foot, confirms? and assigns[:inner_block] == [])

    ~H"""
    <div
      :if={@show}
      id={@id}
      class="dialog"
      phx-hook="ModalTrap"
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div
        class="dialog__panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={@labelledby}
        tabindex="-1"
        phx-click-away={@on_away}
      >
        {render_slot(@inner_block)}

        <h2 :if={@title} id={"#{@id}-title"} class="dialog__title type-h3">{@title}</h2>
        <p :if={@body} class="dialog__body type-body text-secondary">{@body}</p>

        <div :if={@foot} class="dialog__actions">
          <.button kind="secondary" size="md" class="flex-1" phx-click={@on_cancel}>
            {@cancel_label}
          </.button>
          <.button kind={@confirm_kind} size="md" class="flex-1" phx-click={@on_confirm}>
            {@confirm_label}
          </.button>
        </div>
      </div>
    </div>
    """
  end

  defp dialog_confirm_label(true), do: gettext("Remover")
  defp dialog_confirm_label(false), do: gettext("Confirmar")

  # ---------- actions_menu (Sheet + Menu) ----------

  @doc """
  Ações de linha (composição do Penpot: Sheet + Menu). Um único markup: o
  painel é bottom sheet (com título e "Fechar") abaixo de 768 e popover
  âncora no kebab a partir de 768 - a troca é toda do CSS, sem JS de viewport
  (spec 4.3). Fecha por clique fora (`phx-click-away`) e Esc; o painel mobile
  entra no foco (`ModalTrap`).

      <.actions_menu id={"file-\#{file.rkey}"} label={gettext("Mais opções para %{name}", name: file.nome)} title={gettext("Ações do arquivo")}>
        <:item icon="file" navigate={~p"/documentos/\#{file.rkey}"}>{gettext("Abrir")}</:item>
        <:item icon="trash" kind="danger" click={JS.push("ask-delete", value: %{id: file.rkey})}>{gettext("Remover")}</:item>
      </.actions_menu>
  """
  attr :id, :string, required: true
  attr :label, :string, default: gettext("Mais opções")
  attr :title, :string, default: nil

  slot :item, required: true do
    attr :icon, :string
    attr :click, :any
    attr :navigate, :string
    attr :kind, :string, values: ~w(default danger), doc: "Danger: linha de destruição (Remover)"
  end

  def actions_menu(assigns) do
    ~H"""
    <div
      class="actions-menu"
      id={@id}
      phx-click-away={JS.hide(to: "##{@id}-panel")}
      phx-window-keydown={JS.hide(to: "##{@id}-panel") |> JS.focus(to: "##{@id}-trigger")}
      phx-key="escape"
    >
      <button
        type="button"
        id={"#{@id}-trigger"}
        class="actions-menu__trigger icon-button"
        aria-label={@label}
        aria-haspopup="menu"
        aria-expanded="false"
        phx-click={
          JS.toggle(to: "##{@id}-panel", display: "flex")
          |> JS.toggle_attribute({"aria-expanded", "false", "true"})
        }
      >
        <.icon name="kebab" size={20} />
      </button>
      <div id={"#{@id}-panel"} class="actions-menu__panel" phx-hook="ModalTrap">
        <div class="actions-menu__head">
          <p :if={@title} class="actions-menu__title">{@title}</p>
          <button
            type="button"
            class="actions-menu__close"
            phx-click={JS.hide(to: "##{@id}-panel") |> JS.focus(to: "##{@id}-trigger")}
          >
            {gettext("Fechar")}
          </button>
        </div>
        <div class="actions-menu__items">
          <div :for={item <- @item}>
            <.link
              :if={item[:navigate]}
              navigate={item.navigate}
              class={["actions-menu__item", item[:kind] == "danger" && "actions-menu__item--danger"]}
            >
              <.icon :if={item[:icon]} name={item.icon} size={20} />
              <span class="actions-menu__item-label">{render_slot(item)}</span>
            </.link>
            <button
              :if={!item[:navigate]}
              type="button"
              class={["actions-menu__item", item[:kind] == "danger" && "actions-menu__item--danger"]}
              phx-click={JS.concat(JS.hide(to: "##{@id}-panel") |> JS.focus(to: "##{@id}-trigger"), item[:click] || %JS{})}
            >
              <.icon :if={item[:icon]} name={item.icon} size={20} />
              <span class="actions-menu__item-label">{render_slot(item)}</span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
