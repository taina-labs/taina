defmodule TainaWeb.UI.Feedback do
  @moduledoc """
  Feedback de estado do design system (Penpot, "01 - Componentes"), um
  `function component` por linha da tabela (docs/web-revamp-spec.md, 4.1):

  | Nome | Board id |
  | --- | --- |
  | EmptyState | 3fd18cd2-90f8-80f3-8008-d5ab6ceb5dce |
  | ErrorCard | 3fd18cd2-90f8-80f3-8008-d5aed9e21208 |
  | Skeleton | 3fd18cd2-90f8-80f3-8008-d5aa6e1b9bb0 |

  O `flash` (3fd18cd2-90f8-80f3-8008-d5c478e97a78) é o `flash_group/1` que
  já mora em `TainaWeb.CoreComponents`; o CSS é o `flash.css`. O
  `connection_notice` (88db615f-12f9-80b9-8008-d62efd1e77ca) entra aqui por
  ser feedback da conexão (o rascunho da 2.1 o põe nas `Forms`; fica como
  dívida da Wave 4.4 consolidar). Importado pelas telas via `html_helpers`.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  import TainaWeb.Icons
  import TainaWeb.UI.Actions

  @doc """
  Aviso de conexão das telas de auth (Penpot: ConnectionNotice,
  88db615f-12f9-80b9-8008-d62efd1e77ca), exibido só quando a página abriu
  fora do https da própria rede. A decisão de renderizar é do shell
  (`secure_connection?`); o componente é só o markup.

      <.connection_notice />
  """
  def connection_notice(assigns) do
    ~H"""
    <div class="connection-notice">
      <.icon name="info" size={20} class="connection-notice__icon" />
      <p class="connection-notice__text">
        {gettext("Esta conexão só fica protegida quando você está na rede da comunidade. Se não tiver certeza, fale com quem cuida antes de entrar.")}
      </p>
    </div>
    """
  end

  # ---------- estado vazio ----------

  @doc """
  Estado vazio (Penpot: EmptyState, Action yes/no,
  3fd18cd2-90f8-80f3-8008-d5ab6ceb5dce): ícone, título e uma frase; a ação
  da tela entra no slot `:action`.
  """
  attr :icon, :string, default: "folder"
  attr :title, :string, required: true
  attr :body, :string, default: nil, doc: "frase do estado vazio"

  attr :tag, :string,
    default: "p",
    doc: ~S{tag do título (padrão "p"; use "h2" etc. quando a tela tem hierarquia de cabeçalho própria)}

  slot :action, doc: "ação da tela (botão do board)"
  slot :inner_block, doc: "conteúdo extra solto no fim do bloco; prefira o slot :action"

  def empty_state(assigns) do
    ~H"""
    <div class="empty-state">
      <.icon name={@icon} size={40} />
      <.dynamic_tag tag_name={@tag} class="type-h3">{@title}</.dynamic_tag>
      <p :if={@body} class="type-body-sm">{@body}</p>
      <div :if={@action != []}>
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  # ---------- card de erro ----------

  @doc """
  Erro recuperável (Penpot: ErrorCard, 3fd18cd2-90f8-80f3-8008-d5aed9e21208):
  aviso com ícone e o "Tentar de novo" secundário repetindo o evento do
  LiveView. O board traz ainda, ao lado, o "Falar com quem cuida" para quando
  a saída é falar com a pessoa que cuida da nuvem; o evento é opcional.

      <.error_card title="Não conseguimos falar com a nuvem agora." retry_event="retry" />

      <.error_card title="Este convite não é mais válido." retry_event="voltar"
        contact_event="contato" />
  """
  attr :title, :string, required: true
  attr :body, :string, default: nil
  attr :retry_event, :string, required: true, doc: "evento phx-click da ação de repetir"

  attr :retry_label, :string,
    default: nil,
    doc: ~S{rótulo da ação; nil = "Tentar de novo" (o board de auth pede "Voltar")}

  attr :retry_icon, :string, default: "restore", doc: "ícone da ação de repetir"

  attr :contact_event, :string,
    default: nil,
    doc: "evento phx-click do \"Falar com quem cuida\" (opcional)"

  def error_card(assigns) do
    ~H"""
    <div class="error-card">
      <div class="error-card__head">
        <.icon name="warning" size={20} class="error-card__icon" />
        <p class="error-card__title">{@title}</p>
      </div>
      <p :if={@body} class="error-card__body">{@body}</p>
      <div class="error-card__actions">
        <.button kind="secondary" size="sm" icon={@retry_icon} phx-click={@retry_event}>
          {@retry_label || gettext("Tentar de novo")}
        </.button>
        <.button :if={@contact_event} kind="ghost" size="sm" phx-click={@contact_event}>
          {gettext("Falar com quem cuida")}
        </.button>
      </div>
    </div>
    """
  end

  # ---------- aviso de conexão ----------

  # ---------- esqueleto ----------

  @doc """
  Placeholder do estado de carregando, no formato do layout final (nunca
  spinner circular). O `kind` forma umas unidades (linhas de lista, fotos da
  galeria ou card) e `count` repete; sem `kind` fica o bloco solto de antes.
  O CSS mora em `assets/css/components/skeleton.css`.

      <.skeleton kind="list_row" count={4} />
      <.skeleton kind="photo_grid" count={12} />
      <.skeleton class="h-4 w-32" />
  """
  attr :kind, :string, default: nil, values: [nil, "list_row", "photo_grid", "card"]
  attr :count, :integer, default: 1, doc: "quantidade de unidades (só com kind)"
  attr :class, :string, default: ""

  def skeleton(%{kind: nil} = assigns) do
    ~H"""
    <div class={"skeleton " <> assigns.class}></div>
    """
  end

  def skeleton(%{kind: "list_row"} = assigns) do
    assigns = assign(assigns, :count, max(assigns.count, 1))

    ~H"""
    <div class={["skeleton", "skeleton--list-row", @class]}>
      <div :for={_ <- 1..@count} class="skeleton__row">
        <span class="skeleton__mark"></span>
        <span class="skeleton__body">
          <span class="skeleton__line"></span>
          <span class="skeleton__line skeleton__line--short"></span>
        </span>
      </div>
    </div>
    """
  end

  def skeleton(%{kind: "photo_grid"} = assigns) do
    assigns = assign(assigns, :count, max(assigns.count, 1))

    ~H"""
    <div class={["skeleton", "skeleton--photo-grid", @class]}>
      <span :for={_ <- 1..@count} class="skeleton__tile"></span>
    </div>
    """
  end

  def skeleton(%{kind: "card"} = assigns) do
    assigns = assign(assigns, :count, max(assigns.count, 1))

    ~H"""
    <div class={["skeleton", "skeleton--card", @class]}>
      <div :for={_ <- 1..@count} class="skeleton__card">
        <span class="skeleton__line skeleton__line--title"></span>
        <span class="skeleton__line"></span>
        <span class="skeleton__line skeleton__line--short"></span>
      </div>
    </div>
    """
  end
end
