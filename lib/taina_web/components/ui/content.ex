defmodule TainaWeb.UI.Content do
  @moduledoc """
  Conteúdo do design system (Penpot, "01 - Componentes"), um `function
  component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | Card | 3fd18cd2-90f8-80f3-8008-d5ad4993e541 |
  | ServiceSquare | 3fd18cd2-90f8-80f3-8008-d5a0c7a16a64 |
  | Badge | 3fd18cd2-90f8-80f3-8008-d5982f6e1c0e |
  | ListRow | 3fd18cd2-90f8-80f3-8008-d5ac3dfd74d0 |
  | Avatar | 3fd18cd2-90f8-80f3-8008-d59a4a8c891b |
  | Progress | 3fd18cd2-90f8-80f3-8008-d5a9927e3f6b |
  | Steps | 3fd18cd2-90f8-80f3-8008-d5aa706a748c |

  O `chip` não tem componente Penpot (removido na Wave 4) e fica aqui por
  enquanto. `service_card`, `storage_card`, `status_line` e `care_line`
  chegam na Wave 1. Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.Icons

  # ---------- cartões ----------

  @doc "Cartão base do design system (Penpot: Card, 3fd18cd2-90f8-80f3-8008-d5ad4993e541)."

  attr :raised, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={["card", @raised && "card--raised", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc """
  Quadradinho de ícone com a cor do serviço (Ybira verde, Jaci dourado...).
  """
  attr :service, :string,
    default: "neutral",
    values: ~w(ybira jaci nhaman guara maraca doc video neutral)

  attr :icon, :string, required: true
  attr :size, :string, default: "md", values: ~w(md lg)

  def service_square(assigns) do
    ~H"""
    <span class={["service-square service-square--#{@service}", @size == "lg" && "service-square--lg"]}>
      <.icon name={@icon} size={if @size == "lg", do: 24, else: 20} />
    </span>
    """
  end

  # ---------- chips & badges ----------

  @doc "Chip transicional: não tem componente Penpot (removido na Wave 4)."

  attr :selected, :boolean, default: false
  attr :rest, :global
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <button type="button" class="chip" aria-pressed={to_string(@selected)} {@rest}>
      {render_slot(@inner_block)}
    </button>
    """
  end

  @doc "Badge do design system (Penpot: Badge, 3fd18cd2-90f8-80f3-8008-d5982f6e1c0e)."

  attr :variant, :string, required: true, values: ~w(zelador soon active inactive ybira jaci)
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={"badge badge--#{@variant}"}>{render_slot(@inner_block)}</span>
    """
  end

  # ---------- listas ----------

  @doc """
  Linha de lista: ícone/avatar à esquerda, título + meta, ações à direita.
  Cada linha é um `<li>`: as telas agrupam as linhas em `<ul class="list">`.
  Quando a linha convive com outro conteúdo no mesmo item (uma barra de
  progresso, por exemplo), passe `tag="div"` e mantenha o grupo como
  `<div class="list">`.

      <ul class="list">
        <.list_row title="Estatuto.pdf" meta="PDF, 1,1 MB">
          <:leading><.service_square service="doc" icon="file" /></:leading>
          <:actions><.icon_button name="kebab" label="Mais opções" /></:actions>
        </.list_row>
      </ul>
  """
  attr :title, :string, required: true
  attr :meta, :string, default: nil
  attr :meta_class, :string, default: nil
  attr :navigate, :string, default: nil
  attr :tag, :string, default: "li"
  attr :rest, :global
  slot :leading
  slot :actions

  def list_row(assigns) do
    ~H"""
    <.dynamic_tag tag_name={@tag} class="list-row" {@rest}>
      {render_slot(@leading)}
      <.link :if={@navigate} navigate={@navigate} class="list-row__body">
        <p class="list-row__title">{@title}</p>
        <p :if={@meta} class={["list-row__meta", @meta_class]}>{@meta}</p>
      </.link>
      <div :if={!@navigate} class="list-row__body">
        <p class="list-row__title">{@title}</p>
        <p :if={@meta} class={["list-row__meta", @meta_class]}>{@meta}</p>
      </div>
      <div :if={@actions != []} class="list-row__actions">
        {render_slot(@actions)}
      </div>
    </.dynamic_tag>
    """
  end

  # ---------- avatar ----------

  @doc """
  Avatar com inicial e cor determinística a partir do nome.
  """
  attr :name, :string, required: true
  attr :size, :string, default: "md", values: ~w(sm md)
  attr :inactive, :boolean, default: false

  def avatar(assigns) do
    ~H"""
    <span class={["avatar", @size == "sm" && "avatar--sm", avatar_color(@name, @inactive)]}>
      {@name |> String.first() |> String.upcase()}
    </span>
    """
  end

  defp avatar_color(_name, true), do: "avatar--off"
  defp avatar_color(name, false), do: "avatar--#{:erlang.phash2(name, 4)}"

  # ---------- progresso ----------

  @doc """
  Barra de progresso. Aceita `value` como porcentagem (0..100) ou fração (0..1);
  o preenchimento usa `transform: scaleX()`. Para a versão segmentada
  (armazenamento por tipo), passe `segments` como lista de `{cor, fração}`.
  """
  attr :value, :any, default: nil, doc: "porcentagem 0..100 ou fração 0..1"
  attr :label, :string, default: nil, doc: "rótulo acessível (aria-label)"
  attr :color, :string, default: nil, values: [nil, "success", "jaci", "sky", "ybira", "neutral"]
  attr :segments, :list, default: nil, doc: ~s|ex.: [{"jaci", 0.5}, {"sky", 0.3}]|

  def progress(%{segments: segments} = assigns) when is_list(segments) do
    ~H"""
    <div class="progress" role="presentation">
      <div
        :for={{color, fraction} <- @segments}
        class={"progress__fill progress__fill--#{color}"}
        style={"width: #{Float.round(fraction * 100, 2)}%"}
      >
      </div>
    </div>
    """
  end

  def progress(assigns) do
    assigns = assign(assigns, :percent, progress_percent(assigns.value))

    ~H"""
    <div
      class="progress"
      role="progressbar"
      aria-label={@label}
      aria-valuenow={@percent}
      aria-valuemin="0"
      aria-valuemax="100"
    >
      <div
        :if={@percent}
        class={["progress__fill", @color && "progress__fill--#{@color}"]}
        style={"width: 100%; transform-origin: left; transform: scaleX(#{@percent / 100})"}
      >
      </div>
    </div>
    """
  end

  defp progress_percent(nil), do: nil
  defp progress_percent(value) when is_float(value) and value <= 1.0, do: clamp_percent(value * 100)
  defp progress_percent(value), do: clamp_percent(value)

  defp clamp_percent(pct), do: pct |> max(0) |> min(100)

  # ---------- passos do wizard ----------

  @doc "Passos do wizard de setup (Penpot: Steps, 3fd18cd2-90f8-80f3-8008-d5aa706a748c)."

  attr :total, :integer, default: 3
  attr :current, :integer, required: true

  def steps(assigns) do
    ~H"""
    <div
      class="steps"
      role="group"
      aria-label={gettext("Passo %{current} de %{total}", current: @current, total: @total)}
    >
      <span :for={step <- 1..@total} class={["steps__dot", step == @current && "steps__dot--current"]}></span>
    </div>
    """
  end
end
