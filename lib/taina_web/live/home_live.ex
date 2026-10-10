defmodule TainaWeb.HomeLive do
  @moduledoc """
  Home "superapp": saudação, cartão de armazenamento, cards de serviço
  (Arquivos/Fotos/Membros e Mensagens "em breve") e os envios recentes.
  Tela "Home - Superapp" (mobile) e "Desktop - Home" do Penpot.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    # A home degrada em vez de cair: se o Ybira falhar, avisamos por flash e
    # mostramos a tela com as listas vazias (o empty_state assume o lugar) em
    # vez de derrubar a LiveView.
    {recent, ok?} = unwrap(Ybira.list_recent(scope, limit: 4), [])

    socket =
      socket
      |> assign(:page_title, gettext("Início"))
      |> assign(:recent, recent)

    {:ok, maybe_warn(socket, ok?)}
  end

  defp unwrap(result, default, ok? \\ true)
  defp unwrap({:ok, value}, _default, ok?), do: {value, ok?}
  defp unwrap(_error, default, _ok?), do: {default, false}

  defp maybe_warn(socket, true), do: socket

  defp maybe_warn(socket, false) do
    Phoenix.LiveView.put_flash(
      socket,
      :error,
      gettext("Não foi possível carregar tudo agora. Tente recarregar em instantes.")
    )
  end

  # Saudação pelo relógio da caixa, o servidor mora na casa da comunidade,
  # então o horário local do sistema é o horário local de quem usa.
  defp greeting do
    {_date, {hour, _min, _sec}} = :calendar.local_time()

    cond do
      hour in 5..11 -> gettext("Bom dia,")
      hour in 12..17 -> gettext("Boa tarde,")
      true -> gettext("Boa noite,")
    end
  end

  # O mesmo cálculo do card "Espaço da comunidade" (files_live): quanto do
  # espaço da comunidade está em uso, 0..100. Sem cota definida, barra zerada.
  defp storage_percent(%{used_bytes: used, quota_bytes: quota}) when is_integer(quota) and quota > 0,
    do: round(used / quota * 100)

  defp storage_percent(_stats), do: 0

  defp recent_meta(file) do
    "#{file_kind(file.mime_type)}, #{format_bytes(file.file_size_bytes)}, #{relative_time(file.inserted_at)}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:home}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <div class="row between mb-6">
        <div>
          <p class="type-body text-secondary">{greeting()}</p>
          <h1 class="type-h1">{@current_scope.tekoa.name}</h1>
        </div>
        <.link navigate={~p"/conta"} aria-label={gettext("Sua conta")}>
          <.avatar name={@current_scope.ava.display_name || @current_scope.ava.username} />
        </.link>
      </div>

      <.card :if={@storage_stats} class="mb-6">
        <div class="row between mb-3">
          <p class="type-label">{gettext("Espaço da comunidade")}</p>
          <p :if={@storage_stats.quota_bytes} class="type-caption text-success">
            {format_bytes(@storage_stats.quota_bytes - @storage_stats.used_bytes)} {gettext("livres")}
          </p>
        </div>
        <.progress value={storage_percent(@storage_stats)} />
        <p class="type-caption text-muted mt-3">
          {gettext("%{used} de %{total} usados",
            used: format_bytes(@storage_stats.used_bytes),
            total: format_bytes(@storage_stats.quota_bytes)
          )}
        </p>
      </.card>

      <p class="type-overline text-faint mb-3">{gettext("Recentes")}</p>
      <div class="list">
        <.list_row
          :for={file <- @recent}
          title={file.original_filename}
          meta={recent_meta(file)}
          navigate={~p"/arquivos/#{file.public_id}"}
        >
          <:leading>
            <% {service, icon} = file_visual(file.mime_type) %>
            <.service_square service={service} icon={icon} />
          </:leading>
          <:actions>
            <.icon name="chevron-right" size={18} class="text-faint" />
          </:actions>
        </.list_row>
      </div>

      <.empty_state
        :if={@recent == []}
        icon="upload"
        title={gettext("Nada por aqui ainda")}
        hint={gettext("Envie o primeiro arquivo da comunidade.")}
      >
        <.button variant="primary" size="md" navigate={~p"/arquivos/enviar"}>
          {gettext("Enviar arquivos")}
        </.button>
      </.empty_state>
    </Layouts.app>
    """
  end
end
