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
  | ServiceCard | 3fd18cd2-90f8-80f3-8008-d5ab6dd34bf5 |
  | Avatar | 3fd18cd2-90f8-80f3-8008-d59a4a8c891b |
  | Progress | 3fd18cd2-90f8-80f3-8008-d5a9927e3f6b |
  | StorageCard | 3fd18cd2-90f8-80f3-8008-d5ae4c520d6d |
  | StatusLine | 3fd18cd2-90f8-80f3-8008-d5a9ae17253e |
  | CareLine | 3fd18cd2-90f8-80f3-8008-d5adac93ef25 |
  | QRCard | 3fd18cd2-90f8-80f3-8008-d5aef1741a38 |
  | Steps | 3fd18cd2-90f8-80f3-8008-d5aa706a748c |

  O `chip` não tem componente Penpot (removido na Wave 4) e fica aqui por
  enquanto. Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  # ---------- cartões ----------
  import TainaWeb.CoreComponents, only: [format_bytes: 1]
  import TainaWeb.Icons
  import TainaWeb.UI.Actions

  @doc """
  Cartão base do design system (Penpot: Card, Kind default/raised,
  3fd18cd2-90f8-80f3-8008-d5ad4993e541).
  """

  attr :kind, :string, default: nil, values: [nil, "default", "raised"], doc: "Kind do Penpot; nil = default"
  attr :raised, :boolean, default: false, doc: "deprecated: use kind={:raised}"
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    assigns = assign(assigns, :kind, card_kind(assigns[:kind], assigns[:raised]))

    ~H"""
    <div class={["card", @kind == "raised" && "card--raised", @class]} {@rest}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp card_kind(nil, true), do: "raised"
  defp card_kind(nil, _raised), do: "default"
  defp card_kind(kind, _raised), do: kind

  @doc """
  Card de serviço da home (Penpot: ServiceCard, Service ybira/jaci,
  3fd18cd2-90f8-80f3-8008-d5ab6dd34bf5): quadradinho do serviço, título e
  meta, clicável.

      <.service_card service="ybira" title="Documentos" meta="Arquivos da casa e da praça" navigate={~p"/documentos"} />
  """
  attr :service, :string, required: true, values: ~w(ybira jaci)
  attr :title, :string, required: true
  attr :meta, :string, default: nil
  attr :navigate, :string, default: nil

  def service_card(%{navigate: navigate} = assigns) when is_binary(navigate) do
    ~H"""
    <.link navigate={@navigate} class={["service-card", "service-card--#{@service}"]}>
      <.service_square mark={@service} tone="service" size="lg" />
      <p class="service-card__title">{@title}</p>
      <p :if={@meta} class="service-card__meta">{@meta}</p>
    </.link>
    """
  end

  def service_card(assigns) do
    ~H"""
    <div class={["service-card", "service-card--#{@service}"]}>
      <.service_square mark={@service} tone="service" size="lg" />
      <p class="service-card__title">{@title}</p>
      <p :if={@meta} class="service-card__meta">{@meta}</p>
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

  # ---------- chips & badges ----------

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
  Linha de lista (Penpot: ListRow, Kind file/folder/person/civic/mural/
  trash/upload/pedido; Trailing chevron/kebab/action/none;
  State (pedido) esperando/dado/recusado,
  3fd18cd2-90f8-80f3-8008-d5ac3dfd74d0): ícone/avatar à esquerda, título +
  meta, ações à direita. Os textos vêm da tela (`title`/`meta`/slots) e só
  os modificadores BEM saem de `kind`/`trailing`/`state`. Linhas cívicas e
  de mural entram com `<.service_square tone="neutral">` no slot `:leading`.

    * `trailing="chevron"`: o raio brilhante é da linha, sem `:actions` -
      um `<.icon name="chevron-right">` é renderizado pelo componente.
    * `trailing="kebab"` / `trailing="action"`: a tela preenche o slot
      `:actions` (menu de opções ou os botões do board, "Restaurar" etc.).
    * `state` só faz sentido com `kind="pedido"` (esperando/dado/recusado).

  Cada linha é um `<li>`: as telas agrupam as linhas em `<ul class="list">`.
  Quando a linha convive com outro conteúdo no mesmo item (uma barra de
  progresso, por exemplo), passe `tag="div"` e mantenha o grupo como
  `<div class="list">`.

      <ul class="list">
        <.list_row kind="file" title="Estatuto.pdf" meta="PDF, 1,1 MB">
          <:leading><.service_square mark="doc" /></:leading>
          <:actions><.icon_button name="kebab" label="Mais opções" /></:actions>
        </.list_row>
        <.list_row kind="pedido" state="esperando" title="Carla pediu acesso">
          <:actions>
            <.button kind="secondary" size="sm" phx-click="deny">Recusar</.button>
            <.button size="sm" phx-click="allow">Dar acesso</.button>
          </:actions>
        </.list_row>
      </ul>
  """

  attr :kind, :string,
    default: nil,
    values: [nil, "file", "folder", "person", "civic", "mural", "trash", "upload", "pedido"],
    doc: "Kind do Penpot; nil = linha legada, sem modificador"

  attr :trailing, :string,
    default: "none",
    values: ["none", "chevron", "kebab", "action"],
    doc: "Trailing do Penpot; chevron/kebab/action rendem modificador"

  attr :state, :string,
    default: nil,
    values: [nil, "esperando", "dado", "recusado"],
    doc: "só com kind pedido (State do Penpot)"

  attr :title, :string, required: true
  attr :meta, :string, default: nil
  attr :meta_class, :string, default: nil
  attr :navigate, :string, default: nil
  attr :tag, :string, default: "li"
  attr :rest, :global
  slot :leading
  slot :actions

  def list_row(assigns) do
    assigns = assign(assigns, :classes, list_row_classes(assigns[:kind], assigns[:trailing], assigns[:state]))

    ~H"""
    <.dynamic_tag tag_name={@tag} class={@classes} {@rest}>
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
      <.icon :if={@trailing == "chevron"} name="chevron-right" size={18} class="list-row__chevron" />
    </.dynamic_tag>
    """
  end

  defp list_row_classes(kind, trailing, state) do
    [
      "list-row",
      kind && "list-row--#{kind}",
      trailing != "none" && "list-row--#{trailing}",
      state && "list-row--#{state}"
    ]
    |> Enum.reject(&(&1 in [nil, false]))
    |> Enum.join(" ")
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
  attr :color, :string, default: nil, values: [nil, "success", "jaci", "sky", "ybira", "neutral", "warning"]
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

  # ---------- armazenamento ----------

  @doc """
  Espaço da comunidade (Penpot: StorageCard, Detail compact/full, Tone
  normal/warning, 3fd18cd2-90f8-80f3-8008-d5ae4c520d6d). O tom deriva do
  próprio uso: `TainaWeb.Saude.disk_attention?/1` decide o aviso (90%), e o
  card repete o aviso no modifier `--warning`, na barra
  (`progress__fill--warning`) e na frase do board.

  Sem cota (`quota_bytes: nil`, disco inteiro) não existe limite para
  mostrar: nada de barra, a linha vira "Usando o disco inteiro".

      <.storage_card stats={@storage_stats} detail="compact" navigate={~p"/armazenamento"} />
  """

  attr :stats, :map, required: true, doc: "%{used_bytes:, quota_bytes:} (nil = disco inteiro)"

  attr :detail, :string,
    default: "compact",
    values: ~w(compact full),
    doc: "Detail do Penpot: resumo (hub) ou completo (armazenamento)"

  attr :navigate, :string, default: nil, doc: "destino do \"Ver detalhes\" (só no compact)"

  def storage_card(assigns) do
    assigns = assign(assigns, :attention, TainaWeb.Saude.disk_attention?(assigns.stats))

    ~H"""
    <div class={["storage-card", "storage-card--#{@detail}", @attention && "storage-card--warning"]}>
      <div class="storage-card__head">
        <p class="storage-card__label">{gettext("Espaço da comunidade")}</p>
        <.link :if={@detail == "compact" and @navigate} navigate={@navigate} class="storage-card__link">
          {gettext("Ver detalhes")}
        </.link>
      </div>

      <.storage_hero :if={@detail == "full"} stats={@stats} />

      <.progress
        :if={storage_limited?(@stats)}
        value={storage_usage_percent(@stats)}
        color={@attention && "warning" || "success"}
        label={gettext("Espaço da comunidade")}
      />

      <.storage_lines stats={@stats} detail={@detail} attention={@attention} />
    </div>
    """
  end

  # Caixa sem cota: nada de barra e nada de "livres" para medir.
  defp storage_limited?(%{quota_bytes: quota}), do: is_integer(quota) and quota > 0
  defp storage_limited?(_stats), do: false

  # Uso da cota, 0..100 (o used pode passar da cota; a barra tem clamp).
  defp storage_usage_percent(%{used_bytes: used, quota_bytes: quota}) when is_integer(quota) and quota > 0,
    do: used / quota * 100

  defp storage_usage_percent(_stats), do: 0

  defp storage_hero(%{stats: %{used_bytes: used, quota_bytes: quota}} = assigns) when is_integer(quota) and quota > 0 do
    assigns = assign(assigns, used_text: format_bytes(used), total_text: format_bytes(quota))

    ~H"""
    <p class="storage-card__hero type-h2">{gettext("%{used} de %{total}", used: @used_text, total: @total_text)}</p>
    """
  end

  defp storage_hero(%{stats: %{used_bytes: used, disk_bytes: disk}} = assigns) when is_integer(disk) and disk > 0 do
    assigns = assign(assigns, used_text: format_bytes(used), total_text: format_bytes(disk))

    ~H"""
    <p class="storage-card__hero type-h2">
      {gettext("Usando o disco inteiro: %{used} de %{total}", used: @used_text, total: @total_text)}
    </p>
    """
  end

  defp storage_hero(assigns), do: ~H""

  attr :stats, :map, required: true
  attr :detail, :string, required: true
  attr :attention, :boolean, required: true

  defp storage_lines(%{stats: %{used_bytes: used, quota_bytes: quota}} = assigns) when is_integer(quota) and quota > 0 do
    assigns =
      assign(assigns,
        used_text: format_bytes(used),
        total_text: format_bytes(quota),
        free: format_bytes(max(quota - used, 0))
      )

    ~H"""
    <p :if={@detail == "compact"} class="storage-card__meta">
      {gettext("%{used} de %{total} usados", used: @used_text, total: @total_text)}
    </p>
    <p :if={@detail == "full"} class="storage-card__free">
      {gettext("%{free} livres", free: @free)}
    </p>
    <p :if={@attention} class="storage-card__hint">{storage_hint(@detail)}</p>
    """
  end

  # Sem cota: o board do disco inteiro também mostra "N livres" quando a tela
  # sabe o tamanho do disco; sem esse número, a linha do disco inteiro fica
  # sozinha em vez de inventar folga.
  defp storage_lines(%{stats: %{used_bytes: used, disk_bytes: disk}} = assigns) when is_integer(disk) and disk > 0 do
    assigns = assign(assigns, free: format_bytes(max(disk - used, 0)))

    ~H"""
    <p :if={@detail == "full"} class="storage-card__free">
      {gettext("%{free} livres", free: @free)}
    </p>
    <p :if={@attention} class="storage-card__hint">{storage_hint(@detail)}</p>
    """
  end

  defp storage_lines(assigns) do
    ~H"""
    <p class="storage-card__meta">{gettext("Usando o disco inteiro")}</p>
    <p :if={@attention} class="storage-card__hint">{storage_hint(@detail)}</p>
    """
  end

  # Frases do board: no compact o aviso é curto ("Quase cheio."); no full
  # entra a dica da lixeira ("Quase cheio, libere espaço na lixeira.").
  defp storage_hint("compact"), do: gettext("Quase cheio.")
  defp storage_hint("full"), do: gettext("Quase cheio, libere espaço na lixeira.")
  defp storage_hint(_detail), do: gettext("Quase cheio.")

  @doc """
  Linha de status (Penpot: StatusLine, Estado ok/attention/problem/unknown e
  Detail none/with, 3fd18cd2-90f8-80f3-8008-d5a9ae17253e): ícone + palavra,
  nunca cor sozinha - cada estado tem o próprio ícone (mapa puro
  `status_line_icon/1`).

      <.status_line state="ok" title="Backup em dia" />
      <.status_line state="attention" title="Disco quase cheio" detail="96% em uso" />
  """

  attr :state, :string, required: true, values: ~w(ok attention problem unknown)
  attr :title, :string, required: true
  attr :detail, :string, default: nil, doc: "Detail: with (razão textual do estado); nil = Detail: none"

  def status_line(assigns) do
    assigns = assign(assigns, :icon_name, status_line_icon(assigns.state))

    ~H"""
    <div class={["status-line", "status-line--#{@state}"]}>
      <.icon name={@icon_name} size={20} />
      <div class="status-line__body">
        <p class="status-line__title">{@title}</p>
        <p :if={@detail} class="status-line__detail">{@detail}</p>
      </div>
    </div>
    """
  end

  # Estado -> ícone, mapa puro (a cor nunca é a única informação).
  defp status_line_icon("ok"), do: "check"
  defp status_line_icon("attention"), do: "warning"
  defp status_line_icon("problem"), do: "warning"
  defp status_line_icon("unknown"), do: "dots"

  @doc """
  O único "precisa de você" do app (Penpot: CareLine,
  3fd18cd2-90f8-80f3-8008-d5adac93ef25): card elevado, ícone `pedidos` no
  acento `--service-maraca-soft`, frase do pedido e a ação "Responder".

      <.care_line text={@pedido_line} action_label="Responder" navigate={~p"/conta/pedidos"} />
  """
  attr :text, :string, required: true
  attr :action_label, :string, required: true
  attr :navigate, :string, required: true

  def care_line(assigns) do
    ~H"""
    <.link navigate={@navigate} class="care-line">
      <span class="care-line__mark">
        <.icon name="pedidos" size={20} />
      </span>
      <p class="care-line__text">{@text}</p>
      <span class="care-line__action">
        {@action_label}
        <.icon name="chevron-right" size={18} />
      </span>
    </.link>
    """
  end

  # ---------- QR do convite ----------

  @doc """
  Card do link de convite (Penpot: QRCard, título "LINK DO CONVITE", o QR,
  o link, a frase e o botão "Copiar link",
  3fd18cd2-90f8-80f3-8008-d5aef1741a38). O `rest` vai para o botão: é por ele
  que a tela liga o clipboard (`phx-hook="Clipboard"` + `data-copy`) na Wave
  3. O quadradinho branco do QR segue sendo o bloco `.qr-card` (mesmo markup
  que as telas já usam); o card externo é composto de `.card--raised`.
  """
  attr :svg, :any, required: true, doc: "SVG do QR já renderizado (EQRCode.svg + Phoenix.HTML.raw)"
  attr :link, :string, required: true
  attr :rest, :global

  def qr_card(assigns) do
    ~H"""
    <div class="card card--raised col gap-4">
      <p class="type-overline text-faint">{gettext("LINK DO CONVITE")}</p>
      <div class="qr-card" role="img" aria-label={gettext("QR code do link de convite")}>
        {@svg}
      </div>
      <p class="type-mono-sm">{@link}</p>
      <p class="type-body-sm text-secondary">
        {gettext("Quem entrar vê a praça e ganha uma casa própria. Você pode cancelar quando quiser.")}
      </p>
      <.button kind="primary" {@rest}>{gettext("Copiar link")}</.button>
    </div>
    """
  end

  # ---------- passos do wizard ----------

  @doc """
  Passos do wizard de setup (Penpot: Steps, Current 1-3, com a legenda do
  passo atual, 3fd18cd2-90f8-80f3-8008-d5aa706a748c). O `label` é a legenda
  visível ("Boas-vindas", "Quem cuida", "Armazenamento"); sem ele, o markup
  fica igual ao de antes (só os pontos).
  """

  attr :total, :integer, default: 3
  attr :current, :integer, required: true
  attr :label, :string, default: nil, doc: "legenda do passo atual do board; nil = só os pontos (uso legado)"

  def steps(%{label: nil} = assigns) do
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

  def steps(assigns) do
    ~H"""
    <div class="steps steps--labeled">
      <div
        class="steps"
        role="group"
        aria-label={gettext("Passo %{current} de %{total}", current: @current, total: @total)}
      >
        <span :for={step <- 1..@total} class={["steps__dot", step == @current && "steps__dot--current"]}></span>
      </div>
      <p class="steps__label">{@label}</p>
    </div>
    """
  end
end
