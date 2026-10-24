defmodule TainaWeb.UI.Actions do
  @moduledoc """
  Componentes de ação do design system (Penpot, "01 - Componentes"), um
  `function component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Button | 3fd18cd2-90f8-80f3-8008-d5a17ed6d723 |
  | IconButton | 3fd18cd2-90f8-80f3-8008-d596fe970f1a |

  O `fab` (FAB Enviar arquivo, 3fd18cd2-90f8-80f3-8008-d597f9615561) chega na
  Wave 1. Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component

  import TainaWeb.Icons

  # ---------- botões ----------

  @doc """
  Botão do design system. `navigate`/`patch`/`href` viram link estilizado.

      <.button variant="primary">Começar</.button>
      <.button variant="secondary" navigate={~p"/convite"}>Tenho um convite</.button>
  """
  attr :variant, :string, default: "primary", values: ~w(primary secondary ghost service danger fab)
  attr :size, :string, default: "lg", values: ~w(sm md lg)
  attr :type, :string, default: "button"
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :href, :string, default: nil
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(disabled form method download)
  slot :inner_block, required: true

  def button(%{navigate: nil, patch: nil, href: nil} = assigns) do
    ~H"""
    <button type={@type} class={button_class(@variant, @size, @class)} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  def button(assigns) do
    ~H"""
    <.link navigate={@navigate} patch={@patch} href={@href} class={button_class(@variant, @size, @class)} {@rest}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp button_class("fab", _size, class), do: ["btn btn--fab", class]
  defp button_class(variant, size, class), do: ["btn btn--#{variant} btn--#{size}", class]

  @doc """
  Botão só-ícone (appbar, kebab, ações de linha) com rótulo acessível.
  """
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :danger, :boolean, default: false
  attr :navigate, :string, default: nil
  attr :href, :string, default: nil
  attr :rest, :global, include: ~w(download)

  def icon_button(%{navigate: nil, href: nil} = assigns) do
    ~H"""
    <button type="button" class={["icon-btn", @danger && "icon-btn--danger"]} aria-label={@label} title={@label} {@rest}>
      <.icon name={@name} size={20} />
    </button>
    """
  end

  def icon_button(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      href={@href}
      class={["icon-btn", @danger && "icon-btn--danger"]}
      aria-label={@label}
      title={@label}
      {@rest}
    >
      <.icon name={@name} size={20} />
    </.link>
    """
  end
end
