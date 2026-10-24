defmodule TainaWeb.UI.Feedback do
  @moduledoc """
  Feedback de estado do design system (Penpot, "01 - Componentes"), um
  `function component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | EmptyState | 3fd18cd2-90f8-80f3-8008-d5ab6ceb5dce |
  | Skeleton | 3fd18cd2-90f8-80f3-8008-d5aa6e1b9bb0 |

  `error_card` (3fd18cd2-90f8-80f3-8008-d5aed9e21208) chega na Wave 1.
  Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component

  import TainaWeb.Icons

  # ---------- estado vazio ----------

  attr :icon, :string, default: "folder"
  attr :title, :string, required: true
  attr :hint, :string, default: nil

  attr :tag, :string,
    default: "p",
    doc: ~s{tag do título (padrão "p"; use "h2" etc. quando a tela tem hierarquia de cabeçalho própria)}

  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="empty-state">
      <.icon name={@icon} size={40} />
      <.dynamic_tag tag_name={@tag} class="type-h3">{@title}</.dynamic_tag>
      <p :if={@hint} class="type-body-sm">{@hint}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ---------- esqueleto ----------

  @doc """
  Placeholder do estado de carregando, no formato do layout final (nunca
  spinner circular). O CSS mora em `assets/css/components/skeleton.css`.

      <.skeleton class="h-4 w-32" />
  """
  attr :class, :string, default: ""

  def skeleton(assigns) do
    ~H"""
    <div class={"skeleton " <> assigns.class}></div>
    """
  end
end
