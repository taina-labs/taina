defmodule TainaWeb.CoreComponents do
  @moduledoc """
  Componentes do design system (Penpot, "Cofre da Comunidade - UI v1").
  Cada componente tem o bloco CSS correspondente em `assets/css/components.css`,
  mantenha os dois em sincronia. Sem Tailwind: classes semânticas + tokens.
  """

  use Phoenix.Component
  use Gettext, backend: TainaWeb.Gettext

  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS
  alias TainaWeb.Icons

  # ---------- ícone ----------

  @doc """
  Ícone outline do design system, SVG inline (`TainaWeb.Icons`).

      <.icon name="folder" />
      <.icon name="trash" size={20} class="text-error" />
  """
  attr :name, :string, required: true, values: Icons.names()
  attr :size, :integer, default: 24
  attr :class, :string, default: nil

  def icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      width={@size}
      height={@size}
      fill="none"
      stroke="currentColor"
      stroke-width="2"
      stroke-linecap="round"
      stroke-linejoin="round"
      class={["icon", @class]}
      aria-hidden="true"
    >
      {Phoenix.HTML.raw(Icons.path!(@name))}
    </svg>
    """
  end

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

  # ---------- campos ----------

  @doc """
  Campo de formulário com rótulo, ajuda e erros. Aceita `Phoenix.HTML.FormField`.

      <.input field={@form[:username]} type="text" label="Nome de usuário" />
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any
  attr :type, :string, default: "text"
  attr :help, :string, default: nil
  attr :icon, :string, default: nil
  attr :field, FormField, doc: "ex.: @form[:username]"
  attr :errors, :list, default: []
  attr :rest, :global, include: ~w(autocomplete placeholder required minlength maxlength inputmode autofocus)

  def input(%{field: %FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error/1))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(assigns) do
    ~H"""
    <div class={["field", @errors != [] && "field--invalid"]}>
      <label :if={@label} for={@id}>{@label}</label>
      <div class="field__control">
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          aria-invalid={@errors != [] && "true" || nil}
          aria-describedby={input_describedby(@id, @help, @errors)}
          {@rest}
        />
        <.icon :if={@icon} name={@icon} size={20} />
      </div>
      <span :if={@help && @errors == []} class="field__help" id={"#{@id}-help"}>{@help}</span>
      <span
        :for={{error, index} <- Enum.with_index(@errors)}
        class="field__error"
        id={"#{@id}-error-#{index}"}
        role="alert"
      >{error}</span>
    </div>
    """
  end

  # O span de ajuda só entra quando não há erro (mesma condição do template).
  defp input_describedby(nil, _help, _errors), do: nil

  defp input_describedby(id, help, errors) do
    help_ids = if help && errors == [], do: ["#{id}-help"], else: []
    error_ids = Enum.with_index(errors, fn _error, index -> "#{id}-error-#{index}" end)

    case help_ids ++ error_ids do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  # ---------- cartões ----------

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
    values: ~w(ybira jaci nhaman guara doc video neutral)

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

      <.list_row title="Estatuto.pdf" meta="PDF, 1,1 MB">
        <:leading><.service_square service="doc" icon="file" /></:leading>
        <:actions><.icon_button name="kebab" label="Mais opções" /></:actions>
      </.list_row>
  """
  attr :title, :string, required: true
  attr :meta, :string, default: nil
  attr :meta_class, :string, default: nil
  attr :navigate, :string, default: nil
  attr :rest, :global
  slot :leading
  slot :actions

  def list_row(assigns) do
    ~H"""
    <div class="list-row" {@rest}>
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
    </div>
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

  # ---------- controle segmentado ----------

  @doc """
  Alternador de visões (Grade / Linha do tempo).

      <.segmented>
        <:option patch={~p"/fotos"} current={@live_action == :grid}>Grade</:option>
        <:option patch={~p"/fotos/linha-do-tempo"} current={@live_action == :timeline}>Linha do tempo</:option>
      </.segmented>
  """
  slot :option, required: true do
    attr :patch, :string, required: true
    attr :current, :boolean
  end

  def segmented(assigns) do
    ~H"""
    <nav class="segmented">
      <.link
        :for={option <- @option}
        patch={option.patch}
        class="segmented__option"
        aria-current={to_string(option[:current] == true)}
      >
        {render_slot(option)}
      </.link>
    </nav>
    """
  end

  # ---------- passos do wizard ----------

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

  # ---------- menu (kebab) ----------

  @doc """
  Menu suspenso acionado por botão de ícone, fechado com clique fora e Esc.
  O rótulo é opcional e cai no `aria-label` do gatilho; passe um mais específico
  quando o contexto ajuda (ex.: `Mais opções para %{name}`).

      <.menu id={"file-menu-\#{file.public_id}"} label={gettext("Mais opções para %{name}", name: file.name)}>
        <:item icon="pencil" click={JS.push("rename", value: %{id: file.public_id})}>Renomear</:item>
        <:item icon="trash" danger click={JS.push("delete", value: %{id: file.public_id})}>Excluir</:item>
      </.menu>
  """
  attr :id, :string, required: true
  attr :icon, :string, default: "kebab"
  attr :label, :string, default: gettext("Mais opções")

  slot :item, required: true do
    attr :icon, :string
    attr :click, :any, required: true
    attr :danger, :boolean
  end

  def menu(assigns) do
    ~H"""
    <div
      class="menu"
      id={@id}
      phx-click-away={JS.hide(to: "##{@id}-list")}
      phx-window-keydown={JS.hide(to: "##{@id}-list")}
      phx-key="escape"
    >
      <button
        type="button"
        class="icon-btn"
        aria-label={@label}
        aria-haspopup="true"
        aria-expanded="false"
        phx-click={
          JS.toggle(to: "##{@id}-list", display: "flex")
          |> JS.toggle_attribute({"aria-expanded", "false", "true"})
        }
      >
        <.icon name={@icon} size={20} />
      </button>
      <div id={"#{@id}-list"} class="menu__list">
        <button
          :for={item <- @item}
          type="button"
          class={["menu__item", item[:danger] && "menu__item--danger"]}
          phx-click={JS.concat(JS.hide(to: "##{@id}-list"), item.click)}
        >
          <.icon :if={item[:icon]} name={item.icon} size={18} />
          {render_slot(item)}
        </button>
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
      phx-mounted={JS.focus_first(to: "##{@id}")}
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

  # ---------- flash ----------

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div class="flash-group" aria-live="polite">
      <.flash_message kind={:info} flash={@flash} />
      <.flash_message kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :kind, :atom, required: true
  attr :flash, :map, required: true

  defp flash_message(assigns) do
    ~H"""
    <button
      :if={message = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      type="button"
      class={"flash flash--#{@kind}"}
      role={if @kind == :error, do: "alert", else: "status"}
      aria-live={if @kind == :error, do: "assertive", else: "polite"}
      phx-hook={if @kind == :info, do: "FlashAutoDismiss"}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide()}
      title={gettext("Fechar aviso")}
    >
      <.icon name={if @kind == :error, do: "alert", else: "info"} size={20} />
      <span class="flex-1">{message}</span>
    </button>
    """
  end

  # ---------- estado vazio ----------

  attr :icon, :string, default: "folder"
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="empty-state">
      <.icon name={@icon} size={40} />
      <p class="type-h3">{@title}</p>
      <p :if={@hint} class="type-body-sm">{@hint}</p>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ---------- esqueleto ----------

  @doc """
  Placeholder do estado de carregando, no formato do layout final (nunca
  spinner circular). O CSS mora em `assets/css/components.css`.

      <.skeleton class="h-4 w-32" />
  """
  attr :class, :string, default: ""

  def skeleton(assigns) do
    ~H"""
    <div class={"skeleton " <> assigns.class}></div>
    """
  end

  # ---------- helpers de formatação ----------

  @doc """
  Aparência do arquivo por MIME: `{serviço, ícone}` para o `service_square/1`.
  Segue a paleta do Penpot: imagem=Jaci (dourado), vídeo=azul, PDF=ember,
  planilha/texto=verde, resto neutro.
  """
  def file_visual("image/" <> _rest), do: {"jaci", "image"}
  def file_visual("video/" <> _rest), do: {"video", "file"}
  def file_visual("audio/" <> _rest), do: {"video", "play"}
  def file_visual("application/pdf"), do: {"doc", "file"}
  def file_visual("text/" <> _rest), do: {"ybira", "file"}
  def file_visual(_mime), do: {"neutral", "file"}

  @doc """
  Rótulo curto do tipo de arquivo para as linhas de lista ("PDF", "Imagem"...).
  """
  def file_kind("image/" <> _rest), do: gettext("Imagem")
  def file_kind("video/" <> _rest), do: gettext("Vídeo")
  def file_kind("audio/" <> _rest), do: gettext("Áudio")
  def file_kind("application/pdf"), do: "PDF"
  def file_kind("application/zip"), do: "ZIP"
  def file_kind("text/" <> _rest), do: gettext("Texto")
  def file_kind(_mime), do: gettext("Arquivo")

  @doc """
  Bytes em texto humano, convenção pt-BR (vírgula decimal): `format_bytes(2_400_000)` retorna `"2,4 MB"`.
  """
  def format_bytes(nil), do: "0 B"
  def format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"

  def format_bytes(bytes) do
    {value, unit} =
      cond do
        bytes >= 1024 ** 4 -> {bytes / 1024 ** 4, "TB"}
        bytes >= 1024 ** 3 -> {bytes / 1024 ** 3, "GB"}
        bytes >= 1024 ** 2 -> {bytes / 1024 ** 2, "MB"}
        true -> {bytes / 1024, "KB"}
      end

    formatted =
      if value >= 10 do
        value |> round() |> Integer.to_string()
      else
        value |> Float.round(1) |> :erlang.float_to_binary(decimals: 1) |> String.replace(".", ",")
      end

    "#{formatted} #{unit}"
  end

  @doc """
  Tempo relativo curto em pt-BR: "hoje", "ontem", "há 3 dias", "há 2 semanas".
  """
  def relative_time(%NaiveDateTime{} = at) do
    days = Date.diff(Date.utc_today(), NaiveDateTime.to_date(at))

    cond do
      days <= 0 -> gettext("hoje")
      days == 1 -> gettext("ontem")
      days < 7 -> gettext("há %{count} dias", count: days)
      days < 14 -> gettext("há 1 semana")
      days < 30 -> gettext("há %{count} semanas", count: div(days, 7))
      days < 60 -> gettext("há 1 mês")
      true -> gettext("há %{count} meses", count: div(days, 30))
    end
  end

  def relative_time(_other), do: ""

  @doc """
  Tradução de erros de changeset. As mensagens do Ecto chegam em inglês com
  interpolação `%{count}`; aqui interpolamos e deixamos a tradução para os
  arquivos `.po` (domínio "errors").
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(TainaWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(TainaWeb.Gettext, "errors", msg, opts)
    end
  end
end
