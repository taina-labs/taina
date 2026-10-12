defmodule TainaWeb.HomeLive do
  @moduledoc """
  Home "superapp": visão geral dos serviços com acesso rápido (Arquivos, Fotos,
  Moradores, Mural, Saúde), cartão de armazenamento e os envios recentes.
  Tela "Home - Superapp" (mobile) e "Desktop - Home" do Penpot.
  """

  use TainaWeb, :live_view

  alias Taina.Ybira
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    # A home degrada em vez de cair: se o Ybira falhar, avisamos por flash e
    # mostramos a tela com as listas vazias em vez de derrubar a LiveView. O
    # estado vazio só aparece quando a lista de verdade está vazia (recent_ok):
    # com erro, o flash explica e o vazio não mente. O card de espaço segue o
    # mesmo caminho (storage_stats_ok): sem resposta, um aviso calmo com
    # "Tentar de novo" ocupa o lugar dele, nunca um card que some em silêncio.
    {recent, ok?} = unwrap(Ybira.list_recent(scope, limit: 4), [])

    socket =
      socket
      |> assign(:page_title, gettext("Início"))
      |> assign(:recent, recent)
      |> assign(:recent_ok, ok?)
      |> assign(:storage_stats_ok, socket.assigns[:storage_stats] != nil)

    {:ok, maybe_warn(socket, ok?)}
  end

  @impl true
  def handle_event("retry-storage", _params, socket) do
    # O assign de stats nasce no shell (`TainaWeb.Hooks`), só no mount: o
    # retry refaz a consulta aqui e remarca o estado do card.
    case Ybira.storage_stats(socket.assigns.current_scope) do
      {:ok, stats} ->
        {:noreply, socket |> assign(:storage_stats, stats) |> assign(:storage_stats_ok, true)}

      _error ->
        {:noreply, assign(socket, :storage_stats_ok, false)}
    end
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

  # Saudação pelo relógio da caixa: o servidor mora na casa da comunidade,
  # então o horário local do sistema é o horário local de quem usa.
  defp greeting do
    {_date, {hour, _min, _sec}} = :calendar.local_time()

    cond do
      hour in 5..11 -> gettext("Bom dia,")
      hour in 12..17 -> gettext("Boa tarde,")
      true -> gettext("Boa noite,")
    end
  end

  # Serviços na ordem da navegação (sidebar). Moradores e Mural são Maracá:
  # cada serviço tem o próprio acento, e Maracá fica neutro em vez de pegar
  # emprestado o acento dos outros.
  defp services do
    [
      {gettext("Arquivos"), gettext("Documentos e pastas"), "ybira", "folder", ~p"/arquivos"},
      {gettext("Fotos"), gettext("Fotos e vídeos"), "jaci", "image", ~p"/fotos"},
      {gettext("Moradores"), gettext("Quem faz parte"), "neutral", "user", ~p"/membros"},
      {gettext("Mural"), gettext("O que aconteceu"), "neutral", "mural", ~p"/mural"},
      {gettext("Saúde"), gettext("Estado da máquina"), "nhaman", "saude", ~p"/saude"}
    ]
  end

  # Cota definida e maior que zero? Sem cota não há "livres" para medir: o card
  # mostra só o uso e esconde a barra (nunca "X de 0 B usados").
  defp quota?(%{quota_bytes: quota}) when is_integer(quota) and quota > 0, do: true
  defp quota?(_stats), do: false

  # O mesmo cálculo do card "Espaço da comunidade" (files_live): quanto do
  # espaço da comunidade está em uso, 0..100. Sem cota definida, barra zerada.
  defp storage_percent(%{used_bytes: used, quota_bytes: quota}) when is_integer(quota) and quota > 0,
    do: round(used / quota * 100)

  defp storage_percent(_stats), do: 0

  # Quase cheia: 90% ou mais da cota em uso. Aviso em ambiente, nunca alarme:
  # cor + ícone + frase, a cor nunca sozinha.
  defp storage_low?(%{quota_bytes: quota} = stats) when is_integer(quota) and quota > 0, do: storage_percent(stats) >= 90

  defp storage_low?(_stats), do: false

  defp free_label(%{used_bytes: used, quota_bytes: quota} = stats) when is_integer(quota) and quota > 0 do
    free = format_bytes(quota - used)

    if storage_low?(stats) do
      gettext("quase cheia: %{free} livres", free: free)
    else
      gettext("%{free} livres", free: free)
    end
  end

  # Meta da linha recente termina na zona, em palavra (nunca só cor):
  # "Imagem, 2,4 MB, ontem, na praça".
  defp recent_meta(file) do
    [
      file_kind(file.mime_type),
      format_bytes(file.file_size_bytes),
      relative_time(file.inserted_at),
      zona_label(file.zona)
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  defp zona_label(:praca), do: gettext("na praça")
  defp zona_label(_zona), do: gettext("na casa")

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
        <.link navigate={~p"/conta"} class="p-1" aria-label={gettext("Sua conta")}>
          <.avatar name={@current_scope.ava.display_name || @current_scope.ava.username} />
        </.link>
      </div>

      <div class="cards-grid mb-6">
        <.link :for={{label, meta, service, icon, path} <- services()} navigate={path} class="service-card">
          <.service_square service={service} icon={icon} size="lg" />
          <p class="service-card__title">{label}</p>
          <p class="service-card__meta">{meta}</p>
        </.link>
      </div>

      <.card :if={@storage_stats} class="mb-6">
        <div class="row between mb-3">
          <p class="type-label">{gettext("Espaço da comunidade")}</p>
          <p
            :if={quota?(@storage_stats)}
            class={["type-caption", if(storage_low?(@storage_stats), do: "text-warning", else: "text-success")]}
          >
            <.icon :if={storage_low?(@storage_stats)} name="alert" size={14} />
            {free_label(@storage_stats)}
          </p>
        </div>
        <.progress :if={quota?(@storage_stats)} value={storage_percent(@storage_stats)} />
        <p :if={quota?(@storage_stats)} class="type-caption text-muted mt-3">
          <span class="type-mono-sm">{format_bytes(@storage_stats.used_bytes)}</span>
          {gettext("de")}
          <span class="type-mono-sm">{format_bytes(@storage_stats.quota_bytes)}</span>
          {gettext("usados")}
        </p>
        <p :if={!quota?(@storage_stats)} class="type-caption text-muted mt-3">
          <span class="type-mono-sm">{format_bytes(@storage_stats.used_bytes)}</span> {gettext("em uso")}
        </p>
      </.card>

      <.card :if={!@storage_stats_ok} class="mb-6 col gap-3">
        <p class="type-body-sm text-muted">
          {gettext("Não foi possível consultar o espaço da comunidade agora.")}
        </p>
        <.button variant="secondary" size="sm" class="self-start" phx-click="retry-storage">
          {gettext("Tentar de novo")}
        </.button>
      </.card>

      <p class="type-overline text-muted mb-3">{gettext("Recentes")}</p>
      <ul class="list">
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
      </ul>

      <.empty_state
        :if={@recent == [] and @recent_ok}
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
