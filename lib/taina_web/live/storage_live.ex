defmodule TainaWeb.StorageLive do
  @moduledoc """
  Armazenamento (tela "Ybira - Armazenamento"): uso total, barra segmentada
  por tipo e cota da comunidade (zelador edita via `update_tekoa_quota/2`).

  Nota de drift (design vs. backend): o Penpot mostra "cota por membro", mas a
  cota do Maraca é da Tekoa inteira, a UI mostra e edita a cota da
  comunidade até existir cota por pessoa.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Armazenamento"))
     |> assign(:show_quota_modal, false)
     |> load_stats()}
  end

  # Carrega as estatisticas sem derrubar a tela: se o dominio falhar, o
  # empty_state com "Tentar de novo" assume o lugar (sem flash duplicado).
  defp load_stats(socket) do
    scope = socket.assigns.current_scope

    with {:ok, stats} <- Ybira.storage_stats(scope),
         {:ok, by_kind} <- Ybira.storage_stats_by_kind(scope) do
      socket
      |> assign(:stats, stats)
      |> assign(:by_kind, by_kind)
      |> assign(:load_error, false)
    else
      _error ->
        socket
        |> assign(:stats, nil)
        |> assign(:by_kind, [])
        |> assign(:load_error, true)
    end
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, load_stats(socket)}
  end

  def handle_event("toggle-quota-modal", _params, socket) do
    {:noreply, assign(socket, :show_quota_modal, !socket.assigns.show_quota_modal)}
  end

  def handle_event("update-quota", %{"quota" => %{"gigabytes" => gb}}, socket) do
    case parse_gigabytes(gb) do
      {:ok, gigabytes} ->
        case Maraca.update_tekoa_quota(socket.assigns.current_scope, gigabytes * 1024 ** 3) do
          {:ok, _tekoa} ->
            {:noreply,
             socket
             |> assign(:show_quota_modal, false)
             |> Phoenix.LiveView.put_flash(:info, gettext("Cota atualizada."))
             |> load_stats()}

          {:error, _reason} ->
            {:noreply,
             Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível salvar agora. Tente de novo."))}
        end

      # Número inteiro, sem vírgula: "50" vale, "50,5" e "" não. Erro de
      # escrita e erro de salvamento são falas diferentes.
      :error ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Escreva um número inteiro de GB, sem vírgula."))}
    end
  end

  defp parse_gigabytes(gb) do
    case Integer.parse(gb) do
      {gigabytes, ""} when gigabytes > 0 -> {:ok, gigabytes}
      _other -> :error
    end
  end

  # Fração da barra por tipo. As cores são as classes sancionadas do
  # `.progress__fill`, as mesmas da legenda (`legend-dot`): fotos=Jaci,
  # vídeos=azul, documentos=Ybira, resto neutro. Sem o vínculo, a barra
  # inteira pintava de âmbar e meia caixa vazia parecia cheia.
  defp segment_fill(:photos), do: "jaci"
  defp segment_fill(:videos), do: "sky"
  defp segment_fill(:documents), do: "ybira"
  defp segment_fill(:others), do: "neutral"

  defp segments(by_kind, %{used_bytes: used}) when used > 0 do
    for {kind, bytes} <- Enum.sort_by(by_kind, fn {_k, b} -> -b end), bytes > 0 do
      {segment_fill(kind), bytes / used}
    end
  end

  defp segments(_by_kind, _stats), do: []

  defp kind_label(:photos), do: gettext("Fotos")
  defp kind_label(:videos), do: gettext("Vídeos")
  defp kind_label(:documents), do: gettext("Documentos")
  defp kind_label(:others), do: gettext("Outros")

  # "X livres" verde quando o espaço dá folga; âmbar quando sobra pouco (10%
  # ou menos). A palavra "livres" e o número acompanham a cor: cor nunca
  # sozinha.
  defp free_class(%{used_bytes: used, quota_bytes: quota}) when is_integer(quota) and quota > 0 do
    if (quota - used) / quota <= 0.1, do: "text-warning", else: "text-success"
  end

  defp free_class(_stats), do: "text-success"

  # Cota nil não é "0 B" (número que mente): é ausência de limite, dita como
  # estado, o mesmo falar da Saúde.
  defp quota_label(nil), do: gettext("Sem limite definido.")
  defp quota_label(quota), do: format_bytes(quota)

  defp quota_gb(%{quota_bytes: quota}) when is_integer(quota), do: div(quota, 1024 ** 3)
  defp quota_gb(_stats), do: nil

  # Total do grupo "por tipo": a soma do que a pessoa consegue ver (praça,
  # casa dela e o que foi compartilhado com ela). Não é o uso total da Tekoa;
  # aquele é o número grande do card de cima ("Espaço da comunidade").
  defp by_kind_total(by_kind), do: by_kind |> Map.values() |> Enum.sum()

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:account}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <Layouts.app_bar title={gettext("Armazenamento")} back={~p"/conta"} />

      <h1 class="desktop-only type-h1 mb-4 mx-auto w-full measure">{gettext("Armazenamento")}</h1>

      <.empty_state
        :if={@load_error}
        icon="alert"
        title={gettext("Não foi possível carregar")}
        hint={gettext("O armazenamento não respondeu agora.")}
      >
        <.button variant="secondary" phx-click="retry">{gettext("Tentar de novo")}</.button>
      </.empty_state>

      <div :if={@stats} class="col gap-5 mx-auto w-full measure">
        <.card raised class="p-6">
          <p class="type-overline text-muted">{gettext("Espaço da comunidade")}</p>
          <p class="type-display" style="font-family: var(--font-family-mono)">
            {format_bytes(@stats.used_bytes)}
          </p>
          <div class="row between mt-1 mb-4">
            <p :if={@stats.quota_bytes} class="type-body-sm text-muted">
              {gettext("de %{total} usados", total: format_bytes(@stats.quota_bytes))}
            </p>
            <p :if={is_nil(@stats.quota_bytes)} class="type-body-sm text-muted">
              {gettext("Sem limite definido.")}
            </p>
            <p :if={@stats.quota_bytes} class={["type-body-sm", free_class(@stats)]}>
              {format_bytes(@stats.quota_bytes - @stats.used_bytes)} {gettext("livres")}
            </p>
          </div>
          <.progress :if={segments(@by_kind, @stats) != []} segments={segments(@by_kind, @stats)} />
          <.progress :if={segments(@by_kind, @stats) == []} value={0} />
          <p class="type-caption text-muted mt-3">{gettext("Uso por tipo")}</p>
        </.card>

        <p class="type-caption text-muted">
          {gettext("Só entra o que está na praça, a sua casa e o que te deixarem ver. A casa dos outros fica de fora.")}
        </p>

        <div class="list">
          <div :for={{kind, bytes} <- Enum.sort_by(@by_kind, fn {_k, b} -> -b end)} class="list-row">
            <span class={"legend-dot legend-dot--#{kind}"}></span>
            <div class="list-row__body">
              <p class="type-body">{kind_label(kind)}</p>
            </div>
            <p class="type-mono-sm">{format_bytes(bytes)}</p>
          </div>
        </div>
        <p class="type-caption text-muted">
          {gettext("Soma do que você vê: %{total}", total: format_bytes(by_kind_total(@by_kind)))}
        </p>

        <div :if={Maraca.zelador?(@current_scope.ava)}>
          <p class="type-overline text-muted mb-2">{gettext("Cota da comunidade")}</p>
          <button type="button" class="card row between w-full" phx-click="toggle-quota-modal">
            <span class="type-body">{gettext("Limite total")}</span>
            <span class="row gap-2 type-label text-brand">
              {quota_label(@stats.quota_bytes)} <.icon name="chevron-right" size={16} />
            </span>
          </button>
        </div>
      </div>

      <.modal id="quota-modal" show={@show_quota_modal} on_cancel={JS.push("toggle-quota-modal")}>
        <h2 class="type-h3 mb-4">{gettext("Cota da comunidade")}</h2>
        <form id="quota-form" phx-submit="update-quota" class="col gap-4">
          <.input
            label={gettext("Limite total (GB)")}
            type="number"
            name="quota[gigabytes]"
            id="quota_gigabytes"
            value={quota_gb(@stats)}
            help={gettext("Um número inteiro, em GB. Exemplo: 50")}
            inputmode="numeric"
            required
          />
          <div class="row gap-3">
            <.button variant="secondary" size="md" class="flex-1" phx-click="toggle-quota-modal">
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" variant="primary" size="md" class="flex-1">{gettext("Salvar")}</.button>
          </div>
        </form>
      </.modal>
    </Layouts.app>
    """
  end
end
