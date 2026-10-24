defmodule TainaWeb.UI.Actions do
  @moduledoc """
  Componentes de ação do design system (Penpot, "01 - Componentes"), um
  `function component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Button | 3fd18cd2-90f8-80f3-8008-d5a17ed6d723 |
  | IconButton | 3fd18cd2-90f8-80f3-8008-d596fe970f1a |
  | FAB Enviar arquivo | 3fd18cd2-90f8-80f3-8008-d597f9615561 |

  Durante a Wave 1 os componentes emitidos emitem também os aliases legados
  (`.btn*`, `.icon-btn*`, `.btn--fab`), para as telas seguirem compilando sem
  editar as chamadas; a Wave 4.1 remove os aliases.
  """

  use Phoenix.Component

  import TainaWeb.Icons

  # ---------- botões ----------

  @doc """
  Botão do design system (Penpot: Kind primary/secondary/ghost/danger, Size
  sm/md/lg, State loading, Icon none/leading). `navigate`/`patch`/`href`
  viram link estilizado.

      <.button kind="primary">Começar</.button>
      <.button kind="secondary" navigate={~p"/convite"}>Tenho um convite</.button>
  """
  attr :kind, :string, values: ~w(primary secondary ghost danger), doc: "Kind do Penpot; padrão primary"

  attr :variant, :string,
    default: nil,
    doc: "deprecated: use kind. Mapeia 1:1; \"fab\" mantém o quadrado legado até a W4.1"

  attr :size, :string, default: "lg", values: ~w(sm md lg)
  attr :icon, :string, default: nil, doc: "ícone à esquerda (Penpot Icon: leading); \"none\"/omitido = sem ícone"
  attr :loading, :boolean, default: false, doc: "Penpot State: loading; desabilita o controle"
  attr :type, :string, default: "button"
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(form method download)
  slot :inner_block, required: true

  # deprecated: o quadrado FAB legado (`variant="fab"`, sem kind). A W3.2
  # troca o call site pelo `<.fab>`; a W4.1 apaga a cláusula e o alias.
  def button(%{variant: "fab", kind: nil} = assigns) do
    ~H"""
    <.link navigate={@navigate} patch={@patch} href={@href} class={["btn btn--fab", @class]} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  def button(%{navigate: nil, patch: nil, href: nil} = assigns) do
    assigns = resolve_button(assigns)

    ~H"""
    <button
      type={@type}
      class={["button button--#{@kind} button--#{@size}", @loading && "button--loading", "btn btn--#{@kind} btn--#{@size}", @loading && "btn--loading", @class]}
      disabled={@loading || nil}
      aria-busy={@loading && "true" || nil}
      {@rest}
    >
      <.icon :if={@icon_name} name={@icon_name} size={20} />
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button(assigns) do
    assigns = resolve_button(assigns)

    ~H"""
    <.link
      navigate={@navigate}
      patch={@patch}
      href={@href}
      class={["button button--#{@kind} button--#{@size}", @loading && "button--loading", "btn btn--#{@kind} btn--#{@size}", @loading && "btn--loading", @class]}
      aria-disabled={@loading && "true" || nil}
      {@rest}
    >
      <.icon :if={@icon_name} name={@icon_name} size={20} />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp resolve_button(assigns) do
    kind = assigns[:kind] || if assigns[:variant] in [nil, "fab"], do: "primary", else: assigns[:variant]

    assign(assigns, kind: kind, icon_name: leading_icon(assigns[:icon]))
  end

  # Penpot Icon: none | leading; "none"/omitido = sem ícone
  defp leading_icon(nil), do: nil
  defp leading_icon("none"), do: nil
  defp leading_icon(icon), do: icon

  @doc """
  Botão só-ícone (appbar, kebab, ações de linha) com rótulo acessível.
  Penpot Kind: default | danger; o booleano `danger` legado continua aceito.
  """
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :kind, :string, values: ~w(default danger), doc: "Kind do Penpot; padrão default"
  attr :danger, :boolean, default: false, doc: "deprecated: use kind={:danger}"
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :rest, :global, include: ~w(download)

  def icon_button(assigns) do
    assigns = assign(assigns, :kind, assigns[:kind] || (assigns[:danger] && "danger") || "default")

    ~H"""
    <.link
      :if={@navigate || @href}
      navigate={@navigate}
      href={@href}
      class={["icon-button icon-button--#{@kind}", "icon-btn", @kind == "danger" && "icon-btn--danger"]}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <.icon name={@name} size={20} />
    </.link>
    <button
      :if={!@navigate && !@href}
      type="button"
      class={["icon-button icon-button--#{@kind}", "icon-btn", @kind == "danger" && "icon-btn--danger"]}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <.icon name={@name} size={20} />
    </button>
    """
  end

  @doc """
  FAB "Enviar arquivo" (Penpot: FAB Enviar arquivo). Pílula estendida com
  rótulo sempre visível; some no desktop (>= 768 o `service_header` fornece o
  botão "Enviar").
  """
  attr :label, :string, required: true
  attr :icon, :string, default: "plus"
  attr :navigate, :string, default: nil
  attr :uploading, :boolean, default: false, doc: "Penpot State: uploading"
  attr :rest, :global, include: ~w(id)

  def fab(assigns) do
    ~H"""
    <.link
      :if={@navigate}
      navigate={@navigate}
      class={["fab", @uploading && "fab--uploading"]}
      aria-label={@label}
      aria-busy={@uploading && "true" || nil}
      {@rest}
    >
      <.icon name={@icon} size={20} />
      <span class="fab__label">{@label}</span>
    </.link>
    <button
      :if={!@navigate}
      type="button"
      class={["fab", @uploading && "fab--uploading"]}
      disabled={@uploading || nil}
      aria-label={@label}
      aria-busy={@uploading && "true" || nil}
      {@rest}
    >
      <.icon name={@icon} size={20} />
      <span class="fab__label">{@label}</span>
    </button>
    """
  end
end
