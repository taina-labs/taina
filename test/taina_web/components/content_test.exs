defmodule TainaWeb.UI.ContentTest do
  @moduledoc """
  Testes de variante dos componentes de conteúdo: Wave 1a (badge, avatar,
  service_square) e Wave 1b (card kind/raised legado, service_card,
  list_row kinds/trailing/estados de pedido, storage_card compact/full/sem
  cota/atenção, status_line estados + detail, care_line, qr_card, steps com
  e sem label, progress warning).
  """

  use ExUnit.Case, async: true
  use Phoenix.Component

  import Phoenix.LiveViewTest
  import TainaWeb.UI.Content

  # wrapper mínimo por componente (não sombreia o import)

  defp badge_component(assigns) do
    ~H"""
    <.badge kind={@kind} variant={@variant}>{@text}</.badge>
    """
  end

  defp avatar_component(assigns) do
    ~H"""
    <.avatar name={@name} size={@size} off={@off} inactive={@inactive} />
    """
  end

  defp service_square_component(assigns) do
    ~H"""
    <.service_square mark={@mark} service={@service} icon={@icon} tone={@tone} size={@size} />
    """
  end

  defp badge_html(opts) do
    assigns = Enum.into(opts, %{kind: nil, variant: nil, text: "Praça"})
    render_component(&badge_component/1, assigns)
  end

  defp avatar_html(opts \\ []) do
    assigns = Enum.into(opts, %{name: "Ana", size: "md", off: false, inactive: nil})
    render_component(&avatar_component/1, assigns)
  end

  defp square_html(opts \\ []) do
    assigns = Enum.into(opts, %{mark: nil, service: nil, icon: nil, tone: "neutral", size: "md"})
    render_component(&service_square_component/1, assigns)
  end

  # ---------- Badge ----------

  for kind <- ~w(praca casa zelador morador active inactive) do
    test "badge kind #{kind}" do
      html = badge_html(kind: unquote(kind))

      assert html =~ ~s(class="badge badge--#{unquote(kind)}")
      assert html =~ "Praça"
    end
  end

  test "badge variant deprecated: zelador passa direto" do
    html = badge_html(kind: nil, variant: "zelador")
    assert html =~ "badge--zelador"
  end

  test "badge variant deprecated: mods apagados mapeiam para kinds novos" do
    assert badge_html(kind: nil, variant: "ybira") =~ "badge--praca"
    assert badge_html(kind: nil, variant: "jaci") =~ "badge--casa"
    assert badge_html(kind: nil, variant: "soon") =~ "badge--inactive"
  end

  test "badge sem kind e sem variant levanta" do
    assert_raise ArgumentError, fn -> badge_html(kind: nil, variant: nil) end
  end

  # ---------- Avatar ----------

  test "avatar md (padrão): cor determinística pelo hash do nome" do
    html = avatar_html()

    assert html =~ "avatar"
    assert html =~ "A"
    assert html =~ ~r/avatar--[0-3]"/
  end

  test "avatar sm" do
    html = avatar_html(size: "sm")
    assert html =~ "avatar--sm"
  end

  test "avatar lg (novo tamanho)" do
    html = avatar_html(size: "lg")
    assert html =~ "avatar--lg"
  end

  test "avatar off: tinta neutra" do
    html = avatar_html(off: true)
    assert html =~ "avatar--off"
    assert html =~ "A"
  end

  test "avatar inactive deprecated mapeia para off" do
    html = avatar_html(inactive: true)
    assert html =~ "avatar--off"
  end

  # ---------- ServiceSquare ----------

  @mark_icons %{
    "ybira" => "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9",
    "jaci" => "m21 15-3.086",
    "maraca" => "M20 13c0 5-3.5",
    "nhaman" => "M5.45 5.11",
    "doc" => "M15 2H6a2 2 0 0 0-2 2v16",
    "video" => "20 12 6 21 6 3",
    "neutral" => "M12 16v-4",
    "casa" => "M4,11.2L12,4L20,11.2",
    "praca" => "M4,19L20,19",
    "lixeira" => "M8.1,13L15.9,13",
    "mural" => "M15 12h-5",
    "saude" => "M2 9.5a5.5",
    "moradores" => "M3.6,19.5C3.6,16.2",
    "pedidos" => "M4,13L8.2,13",
    "privacidade" => "M8.5,10.5L8.5,8",
    "senha" => "M10.2,10.2L20,20",
    "dispositivos" => "M17.6,14.6L19.4,14.6",
    "sair" => "M13,4.5L5.5,4.5"
  }

  for mark <-
        ~w(ybira jaci maraca nhaman doc video neutral casa praca lixeira mural saude moradores pedidos privacidade senha dispositivos sair) do
    test "service_square mark #{mark}: tone neutral (padrão) e ícone derivado" do
      mark = unquote(mark)
      html = square_html(mark: mark)

      assert html =~ "service-square service-square--neutral service-square--#{mark}"
      assert html =~ Map.fetch!(@mark_icons, mark)
    end
  end

  test "service_square tone service" do
    html = square_html(mark: "ybira", tone: "service")

    assert html =~ "service-square--service"
    assert html =~ "service-square--ybira"
  end

  test "service_square size lg" do
    html = square_html(mark: "doc", size: "lg")
    assert html =~ "service-square--lg"
  end

  test "service_square caminho legado service + icon: marca mapeada e ícone do chamador" do
    html = square_html(service: "ybira", icon: "folder")

    assert html =~ "service-square--service service-square--ybira"
    # ícone legado passado (não o derivado do mark)
    assert html =~ "M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9"
  end

  test "service_square caminho legado service desconhecido cai no neutral" do
    html = square_html(service: "guara", icon: "user")
    assert html =~ "service-square service-square--neutral service-square--neutral"
  end

  test "service_square sem mark e sem par legado levanta" do
    assert_raise ArgumentError, fn -> square_html() end
  end

  # ---------- Card (Wave 1b) ----------

  defp card_component(assigns) do
    ~H"""
    <.card kind={@kind} raised={@raised} class={@class}>{@text}</.card>
    """
  end

  defp card_html(opts) do
    assigns = Enum.into(opts, %{kind: nil, raised: false, class: nil, text: "Espaço da comunidade"})
    render_component(&card_component/1, assigns)
  end

  test "card kind default (padrão): sem modifier" do
    html = card_html(kind: "default")

    assert html =~ ~s(class="card)
    refute html =~ "card--"
  end

  test "card kind raised" do
    html = card_html(kind: "raised")
    assert html =~ "card card--raised"
  end

  test "card raised legado continua card--raised" do
    assert card_html(raised: true, kind: nil) =~ "card card--raised"
    assert card_html(raised: true, kind: nil) =~ "Espaço da comunidade"
  end

  # ---------- ServiceCard (Wave 1b) ----------

  defp service_card_component(assigns) do
    ~H"""
    <.service_card service={@service} title={@title} meta={@meta} navigate={@navigate} />
    """
  end

  defp service_card_html(opts) do
    assigns = Enum.into(opts, %{service: nil, title: "Documentos", meta: nil, navigate: nil})
    render_component(&service_card_component/1, assigns)
  end

  for service <- ~w(ybira jaci) do
    test "service_card service #{service}: modifier, quadradinho do serviço e copy do board" do
      service = unquote(service)
      html = service_card_html(service: service, meta: "meta")

      assert html =~ ~s(service-card service-card--#{service}")
      assert html =~ "service-square service-square--service service-square--#{service}"
      assert html =~ "Documentos"
      assert html =~ "meta"
    end
  end

  test "service_card com navigate: link" do
    html = service_card_html(service: "ybira", navigate: "/documentos")

    assert html =~ ~s(href="/documentos")
    assert html =~ "service-card"
  end

  test "service_card sem navigate: card é um div (não clicável)" do
    html = service_card_html(service: "jaci")

    refute html =~ "href"
    assert html =~ ~r/<div class="service-card service-card--jaci"/
  end

  # ---------- ListRow (Wave 1b) ----------

  defp list_row_component(assigns) do
    ~H"""
    <.list_row kind={@kind} title={@title} meta={@meta} navigate={@navigate} trailing={@trailing} state={@state} />
    """
  end

  defp list_row_html(opts) do
    assigns = Enum.into(opts, %{kind: nil, title: "Diretório", meta: nil, navigate: nil, trailing: "none", state: nil})
    render_component(&list_row_component/1, assigns)
  end

  @list_row_kinds ~w(file folder person civic mural trash upload pedido)

  for kind <- @list_row_kinds do
    test "list_row kind #{kind}" do
      kind = unquote(kind)
      html = list_row_html(kind: kind, title: "Diretório", meta: "Hoje, 09:12")

      assert html =~ ~r/list-row list-row--#{kind}/
      assert html =~ "Diretório"
      assert html =~ "Hoje, 09:12"
    end
  end

  test "list_row linha legada sem kind: só o bloco, sem modifier" do
    html = list_row_html(title: "Estatuto.pdf")

    assert html =~ ~s(class="list-row")
    refute html =~ "list-row--"
  end

  test "list_row trailing chevron: modifier e ícone automático da linha" do
    html = list_row_html(kind: "file", trailing: "chevron")

    assert html =~ "list-row--chevron"
    # raio brilhante do componente (path do chevron-right)
    assert html =~ "m9 18 6-6-6-6"
  end

  test "list_row trailing kebab e action: só modifier, ação vem do slot" do
    assert list_row_html(kind: "file", trailing: "kebab") =~ "list-row--kebab"
    # trailing action: o board "Restaurar" (lixeira) renderiza o botão da tela no :actions
    assert list_row_html(kind: "trash", trailing: "action") =~ "list-row--action"
  end

  test "list_row trailing none: sem modifier" do
    refute list_row_html(kind: "file", trailing: "none") =~ "list-row--chevron"
  end

  test "list_row pedido, estado esperando" do
    html = list_row_html(kind: "pedido", state: "esperando", title: "Carla pediu acesso")

    assert html =~ "list-row--pedido"
    assert html =~ "list-row--esperando"
    assert html =~ "Carla pediu acesso"
  end

  test "list_row pedido, estados dado e recusado" do
    assert list_row_html(kind: "pedido", state: "dado", title: "Carla") =~ "list-row--dado"
    assert list_row_html(kind: "pedido", state: "recusado", title: "Carla") =~ "list-row--recusado"
  end

  # ---------- Progress warning (Wave 1b) ----------

  defp progress_component(assigns) do
    ~H"""
    <.progress value={@value} label={@label} color={@color} />
    """
  end

  defp progress_html(opts) do
    assigns = Enum.into(opts, %{value: nil, label: nil, color: nil})
    render_component(&progress_component/1, assigns)
  end

  test "progress tone warning novo" do
    html = progress_html(value: 92, color: "warning", label: "Espaço da comunidade")

    assert html =~ "progress__fill--warning"
    assert html =~ ~s(aria-label="Espaço da comunidade")
  end

  test "progress sem tone continua no brand" do
    html = progress_html(value: 50)

    assert html =~ ~r/class="progress__fill\s"/
    refute html =~ "progress__fill--"
  end

  # ---------- StorageCard (Wave 1b) ----------

  defp storage_card_component(assigns) do
    ~H"""
    <.storage_card stats={@stats} detail={@detail} navigate={@navigate} />
    """
  end

  defp storage_card_html(opts) do
    assigns = Enum.into(opts, %{stats: nil, detail: "compact", navigate: "/armazenamento"})
    render_component(&storage_card_component/1, assigns)
  end

  @normal_stats %{used_bytes: 88_000_000_000, quota_bytes: 256_000_000_000}
  @warning_stats %{used_bytes: 92_000_000_000, quota_bytes: 100_000_000_000}

  test "storage_card compact: label do hub, uso e Ver detalhes" do
    html = storage_card_html(stats: @normal_stats)

    assert html =~ ~s(storage-card storage-card--compact)
    assert html =~ "Espaço da comunidade"
    assert html =~ "Ver detalhes"
    assert html =~ ~s(href="/armazenamento")
    # unidades binárias (1024): 88_000_000_000 bytes = 82 GB e
    # 256_000_000_000 bytes = 238 GB; o meta segue o padrão "X de Y usados".
    assert html =~ "82 GB de 238 GB usados"
    assert html =~ "progress__fill--success"
  end

  test "storage_card full: barra, meta e livres" do
    html = storage_card_html(stats: @normal_stats, detail: "full")

    assert html =~ "storage-card--full"
    assert html =~ "usados"
    assert html =~ "livres"
    # compact só: sem Ver detalhes no full (o card já é o detalhe)
    refute html =~ "Ver detalhes"
  end

  test "storage_card tone warning (disco quase cheio): modifier, barra âmbar e frase do board" do
    html = storage_card_html(stats: @warning_stats, detail: "full")

    assert html =~ "storage-card--warning"
    assert html =~ "storage-card__hint"
    assert html =~ "Quase cheio, libere espaço na lixeira."
    assert html =~ "progress__fill--warning"
  end

  test "storage_card compact em atenção: aviso curto do compact" do
    html = storage_card_html(stats: @warning_stats, detail: "compact")

    assert html =~ "storage-card--warning"
    assert html =~ "Quase cheio."
    refute html =~ "libere espaço na lixeira"
  end

  test "storage_card sem cota: Usando o disco inteiro, sem barra e sem livres" do
    html = storage_card_html(stats: %{used_bytes: 82_000_000_000, quota_bytes: nil}, detail: "full")

    assert html =~ "Usando o disco inteiro"
    refute html =~ "progress__fill"
    refute html =~ "livres"
    refute html =~ "storage-card--warning"
  end

  # ---------- StatusLine (Wave 1b) ----------

  @status_line_icons %{
    "ok" => "M20 6 9 17l-5-5",
    "attention" => ~s(d="M12,2L22,22L2,22Z"),
    "problem" => ~s(d="M12,2L22,22L2,22Z"),
    "unknown" => ~s(cx="19" cy="12")
  }

  defp status_line_component(assigns) do
    ~H"""
    <.status_line state={@state} title={@title} detail={@detail} />
    """
  end

  defp status_line_html(opts) do
    assigns = Enum.into(opts, %{state: nil, title: "Backup em dia", detail: nil})
    render_component(&status_line_component/1, assigns)
  end

  for state <- ~w(ok attention problem unknown) do
    test "status_line state #{state}: modifier, ícone do mapa puro e copy do board (nunca cor sozinha)" do
      state = unquote(state)
      html = status_line_html(state: state)

      assert html =~ "status-line status-line--#{state}"
      assert html =~ Map.fetch!(@status_line_icons, state)
      assert html =~ "Backup em dia"
    end
  end

  test "status_line detail none: sem linha de detalhe" do
    html = status_line_html(state: "ok")
    refute html =~ "status-line__detail"
  end

  test "status_line detail with: a linha de razão do estado" do
    html = status_line_html(state: "attention", title: "Disco quase cheio", detail: "96% em uso")

    assert html =~ "status-line__detail"
    assert html =~ "96% em uso"
  end

  # ---------- CareLine (Wave 1b) ----------

  defp care_line_component(assigns) do
    ~H"""
    <.care_line text={@text} action_label={@action_label} navigate={@navigate} />
    """
  end

  defp care_line_html(opts) do
    assigns = Enum.into(opts, %{text: nil, action_label: nil, navigate: nil})
    render_component(&care_line_component/1, assigns)
  end

  test "care_line: ícone pedidos no square maraca, frase, ação e raio" do
    html =
      care_line_html(
        text: "Carla pediu para abrir um arquivo da sua casa",
        action_label: "Responder",
        navigate: "/conta/pedidos"
      )

    assert html =~ ~s(href="/conta/pedidos")
    assert html =~ "care-line__mark"
    assert html =~ "care-line__text"
    assert html =~ "care-line__action"
    assert html =~ "Carla pediu para abrir um arquivo da sua casa"
    assert html =~ "Responder"
    assert html =~ "m9 18 6-6-6-6"
  end

  # ---------- QRCard (Wave 1b) ----------

  defp qr_card_component(assigns) do
    ~H"""
    <.qr_card svg={@svg} link={@link} />
    """
  end

  defp qr_card_html(opts) do
    assigns = Enum.into(opts, %{svg: nil, link: nil})
    render_component(&qr_card_component/1, assigns)
  end

  test "qr_card: card elevado, quadradinho branco do QR, link e botão de copiar" do
    html = qr_card_html(svg: Phoenix.HTML.raw("<svg viewBox=\"0 0 2 2\"></svg>"), link: "taina.local/c/x7f2a9k3")

    assert html =~ "card card--raised"
    assert html =~ "<svg viewBox=\"0 0 2 2\"></svg>"
    assert html =~ "QR code do link de convite"
    assert html =~ "taina.local/c/x7f2a9k3"
    assert html =~ "Copiar link"
    assert html =~ "button"
  end

  # ---------- Steps com label (Wave 1b) ----------

  defp steps_component(assigns) do
    ~H"""
    <.steps current={@current} total={@total} label={@label} />
    """
  end

  defp steps_html(opts) do
    assigns = Enum.into(opts, %{current: 1, total: 3, label: nil})
    render_component(&steps_component/1, assigns)
  end

  test "steps com label: legenda visível do board e pontos do passo atual" do
    html = steps_html(current: 2, label: "Quem cuida")

    assert html =~ "steps steps--labeled"
    assert html =~ "steps__label"
    assert html =~ "Quem cuida"
    assert html =~ "steps__dot steps__dot--current"
  end

  test "steps sem label (uso legado do setup): só os pontos, sem legenda" do
    html = steps_html(current: 1)

    assert html =~ ~s(class="steps")
    assert html =~ "steps__dot steps__dot--current"
    refute html =~ "steps--labeled"
    refute html =~ "steps__label"
  end
end
