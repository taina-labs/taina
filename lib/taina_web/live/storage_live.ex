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

  # Carrega as estatisticas sem derrubar a tela: se o dominio falhar, avisamos
  # por flash e marcamos `load_error` para o render cair no empty_state em vez
  # de quebrar no match.
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
        |> Phoenix.LiveView.put_flash(:error, gettext("Não foi possível carregar o armazenamento agora."))
    end
  end

  @impl true
  def handle_event("toggle-quota-modal", _params, socket) do
    {:noreply, assign(socket, :show_quota_modal, !socket.assigns.show_quota_modal)}
  end

  def handle_event("update-quota", %{"quota" => %{"gigabytes" => gb}}, socket) do
    with {gigabytes, ""} when gigabytes > 0 <- Integer.parse(gb),
         {:ok, _tekoa} <-
           Maraca.update_tekoa_quota(socket.assigns.current_scope, gigabytes * 1024 ** 3) do
      {:noreply,
       socket
       |> assign(:show_quota_modal, false)
       |> Phoenix.LiveView.put_flash(:info, gettext("Cota atualizada."))
       |> load_stats()}
    else
      _error ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível atualizar a cota."))}
    end
  end

  defp segments(by_kind, %{used_bytes: used}) when used > 0 do
    for {kind, bytes} <- Enum.sort_by(by_kind, fn {_k, b} -> -b end), bytes > 0 do
      {Atom.to_string(kind), bytes / used}
    end
  end

  defp segments(_by_kind, _stats), do: []

  defp kind_label(:photos), do: gettext("Fotos")
  defp kind_label(:videos), do: gettext("Vídeos")
  defp kind_label(:documents), do: gettext("Documentos")
  defp kind_label(:others), do: gettext("Outros")

  defp quota_gb(%{quota_bytes: quota}) when is_integer(quota), do: div(quota, 1024 ** 3)
  defp quota_gb(_stats), do: nil

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

      <.empty_state
        :if={@load_error}
        icon="alert"
        title={gettext("Não foi possível carregar")}
        hint={gettext("O uso de armazenamento não respondeu agora. Tente recarregar em instantes.")}
      />

      <div :if={@stats} class="col gap-5 mx-auto w-full measure">
        <.card raised class="p-6">
          <p class="type-display">{format_bytes(@stats.used_bytes)}</p>
          <div class="row between mt-1 mb-4">
            <p class="type-body-sm text-muted">
              {gettext("de %{total} usados", total: format_bytes(@stats.quota_bytes))}
            </p>
            <p :if={@stats.quota_bytes} class="type-body-sm text-success">
              {format_bytes(@stats.quota_bytes - @stats.used_bytes)} {gettext("livres")}
            </p>
          </div>
          <.progress :if={segments(@by_kind, @stats) != []} segments={segments(@by_kind, @stats)} />
          <.progress :if={segments(@by_kind, @stats) == []} value={0} />
          <p class="type-caption text-faint mt-3">{gettext("Uso por tipo")}</p>
        </.card>

        <div class="list">
          <div :for={{kind, bytes} <- Enum.sort_by(@by_kind, fn {_k, b} -> -b end)} class="list-row">
            <span class={"legend-dot legend-dot--#{kind}"}></span>
            <div class="list-row__body">
              <p class="type-body">{kind_label(kind)}</p>
            </div>
            <p class="type-label">{format_bytes(bytes)}</p>
          </div>
        </div>

        <div :if={Maraca.zelador?(@current_scope.ava)}>
          <p class="type-overline text-faint mb-2">{gettext("Cota da comunidade")}</p>
          <button type="button" class="card row between w-full" phx-click="toggle-quota-modal">
            <span class="type-body">{gettext("Limite total")}</span>
            <span class="row gap-2 type-label text-brand">
              {format_bytes(@stats.quota_bytes)} <.icon name="chevron-right" size={16} />
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
