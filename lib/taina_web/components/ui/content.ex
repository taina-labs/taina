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
  Quadradinho de ícone (Penpot: ServiceSquare). A marca `mark` define o
  documento visual e deriva o ícone por mapa puro (`mark_icon/1`). `tone`
  (service | neutral) escolhe o fundo; padrão neutral.

      <.service_square mark="doc" />
      <.service_square mark="ybira" tone="service" size="lg" />
  """
  @marks ~w(ybira jaci maraca nhaman doc video neutral casa praca lixeira mural saude moradores pedidos privacidade senha dispositivos sair)

  attr :mark, :string, values: @marks, doc: "marca do Penpot; o ícone sai do mapa puro mark_icon/1"
  attr :service, :string, default: nil, doc: "deprecated: use mark; mapeia 1:1 e exige o `icon` legado"
  attr :icon, :string, default: nil, doc: "deprecated: só com :service; o ícone novo é derivado do mark"
  attr :tone, :string, default: "neutral", values: ~w(service neutral)
  attr :size, :string, default: "md", values: ~w(md lg)

  def service_square(%{mark: mark} = assigns) when is_binary(mark) do
    assigns
    |> assign(icon_name: mark_icon(mark))
    |> render_service_square()
  end

  # deprecated: `<.service_square service="ybira" icon="folder" />` nas telas
  # segue compilando (W3 reescreve as chamadas; W4.1 apaga a cláusula). O
  # serviço legado entra como mark; o ícone continua sendo o passado.
  def service_square(%{service: service, icon: icon} = assigns) when is_binary(service) and is_binary(icon) do
    mark = service_mark(service)

    assigns
    |> assign(mark: mark, tone: service_tone(mark), icon_name: icon)
    |> render_service_square()
  end

  def service_square(_assigns) do
    raise ArgumentError, "service_square: informe :mark (ou o par legado :service + :icon)"
  end

  defp render_service_square(assigns) do
    ~H"""
    <span class={["service-square", "service-square--#{@tone}", "service-square--#{@mark}", @size == "lg" && "service-square--lg"]}>
      <.icon name={@icon_name} size={if @size == "lg", do: 24, else: 20} />
    </span>
    """
  end

  # mapa puro mark -> ícone do design system (docs/web-revamp-spec.md, 4.1)
  @mark_icons %{
    "ybira" => "folder",
    "jaci" => "image",
    "maraca" => "shield",
    "nhaman" => "disk",
    "doc" => "file",
    "video" => "play",
    "neutral" => "info",
    "casa" => "casa",
    "praca" => "praca",
    "lixeira" => "lixeira",
    "mural" => "mural",
    "saude" => "saude",
    "moradores" => "moradores",
    "pedidos" => "pedidos",
    "privacidade" => "privacidade",
    "senha" => "senha",
    "dispositivos" => "dispositivos",
    "sair" => "sair"
  }

  defp mark_icon(mark), do: Map.fetch!(@mark_icons, mark)

  defp service_mark(service), do: if(service in @marks, do: service, else: "neutral")

  defp service_tone(mark) when mark in ~w(ybira jaci maraca nhaman), do: "service"
  defp service_tone(_mark), do: "neutral"

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

  @doc """
  Badge do design system (Penpot Badge: Kind praca/casa/zelador/morador/
  active/inactive). Cores só dos tokens `--badge-*` (docs/web-revamp-spec.md,
  4.1); `variant` continua aceito até a Wave 4.
  """
  attr :kind, :string, values: ~w(praca casa zelador morador active inactive)
  attr :variant, :string, default: nil, doc: "deprecated: use kind (os mods ybira/jaci/soon mapeiam para kinds novos)"
  slot :inner_block, required: true

  def badge(assigns) do
    assigns = assign(assigns, :kind, assigns[:kind] || badge_kind!(assigns[:variant]))

    ~H"""
    <span class={"badge badge--#{@kind}"}>{render_slot(@inner_block)}</span>
    """
  end

  # deprecated: variant -> kind. Os valores sem kind novo vão para o vizinho
  # mais próximo até a W3 reescrever as chamadas.
  defp badge_kind!(nil) do
    raise ArgumentError, "badge: informe :kind (ou o :variant legado)"
  end

  defp badge_kind!("ybira"), do: "praca"
  defp badge_kind!("jaci"), do: "casa"
  defp badge_kind!("soon"), do: "inactive"
  defp badge_kind!(variant), do: variant

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
  Avatar com inicial e cor determinística a partir do nome. Size: sm, md, lg.
  `off` apaga a cor (Penpot Tint: off); o booleano `inactive` legado segue
  aceito.
  """
  attr :name, :string, required: true
  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :off, :boolean, default: false
  attr :inactive, :boolean, default: nil, doc: "deprecated: use off"

  def avatar(assigns) do
    assigns = assign(assigns, :off, assigns[:off] == true or assigns[:inactive] == true)

    ~H"""
    <span class={["avatar", @size in ~w(sm lg) && "avatar--#{@size}", avatar_color(@name, @off)]}>
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
