defmodule TainaWeb.MuralLive do
  @moduledoc """
  Mural (RFC_003 seção 6, camada 1): o livro-caixa do "quem fez o quê", em frases
  simples, do mais recente para o mais antigo, agrupado por dia.

  Somente leitura para todos os papéis, zelador(a) incluso: o mural é registro
  do que aconteceu, não é um lugar de agir, então não há filtro nem controle
  que sugira poder sobre o registro. Os eventos chegam paginados por offset
  (`Maraca.list_events/2`) e são agrupados no stream: o rótulo do dia vai na
  primeira ocorrência de cada data.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Event
  alias TainaWeb.Layouts
  alias TainaWeb.Time

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Mural"))
     |> assign(:next_offset, nil)
     |> assign(:headed_dates, MapSet.new())
     |> assign(:event_count, 0)
     |> assign(:load_error, false)
     |> assign_events()}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    if offset = socket.assigns.next_offset do
      case Maraca.list_events(socket.assigns.current_scope, offset: offset) do
        {:ok, %{events: events, next_offset: next}} ->
          {entries, headed} = page_entries(events, socket.assigns.headed_dates)

          {:noreply,
           socket
           |> assign(:next_offset, next)
           |> assign(:headed_dates, headed)
           |> assign(:event_count, socket.assigns.event_count + length(entries))
           |> stream(:events, entries)}

        {:error, _reason} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível carregar mais do mural."))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("retry", _params, socket) do
    {:noreply, assign_events(socket)}
  end

  # Carrega a primeira página sem derrubar a tela: se o mural falhar, o
  # empty_state com "Tentar de novo" assume o lugar (sem flash duplicado).
  defp assign_events(socket) do
    case Maraca.list_events(socket.assigns.current_scope) do
      {:ok, %{events: events, next_offset: next}} ->
        {entries, headed} = page_entries(events, socket.assigns.headed_dates)

        socket
        |> assign(:next_offset, next)
        |> assign(:headed_dates, headed)
        |> assign(:event_count, socket.assigns.event_count + length(entries))
        |> assign(:load_error, false)
        |> stream(:events, entries, reset: true)

      {:error, _reason} ->
        assign(socket, :load_error, true)
    end
  end

  # --- core puro: dados -> dados ---

  # Modela a página para o render: frase pronta, quando relativo, e o rótulo
  # do dia só na primeira ocorrência da data. `headed_dates` carrega as datas
  # que já ganharam rótulo, então uma data que continua de página anterior
  # não repete o cabeçalho. Datas no horário da comunidade (o banco grava em
  # UTC; o dia de quem lê não é o dia do banco).
  defp page_entries(events, headed_dates) do
    Enum.map_reduce(events, headed_dates, fn event, headed ->
      date = Time.local_date(event.inserted_at)

      if MapSet.member?(headed, date) do
        {entry(event, nil), headed}
      else
        {entry(event, day_title(date)), MapSet.put(headed, date)}
      end
    end)
  end

  defp entry(%Event{} = event, day_label) do
    %{
      id: event.id,
      day_label: day_label,
      sentence: sentence(event),
      ago: ago_label(event.inserted_at)
    }
  end

  # Rótulo do grupo de dia, o mesmo da linha do tempo do Jaci.
  defp day_title(date) do
    case Date.diff(Time.local_today(), date) do
      0 -> gettext("Hoje")
      1 -> gettext("Ontem")
      _days -> Calendar.strftime(date, "%d/%m/%Y")
    end
  end

  # Sob "Hoje"/"Ontem" a hora basta: repetir "hoje" em cada linha é eco, não
  # informação. Dias mais velhos ficam com o tempo relativo do design system.
  defp ago_label(at) do
    if Date.diff(Time.local_today(), Time.local_date(at)) in 0..1,
      do: Time.local_clock(at),
      else: relative_time(at)
  end

  # Ator em início de frase: nome de exibição quando existe, senão o nome de
  # usuário; sem autor (ato do sistema), "O sistema".
  defp actor_label(%Event{ava: %Ava{} = ava}), do: ava.display_name || ava.username
  defp actor_label(%Event{}), do: gettext("O sistema")

  # Frases do mural: cada `type` vira uma frase simples, sem IDs e sem jargão.
  # Se um ato não cabe numa frase, o problema é o `type`, não a frase.
  defp sentence(%Event{type: :invite_created} = event) do
    if event.payload["role"] == "zelador" do
      gettext("%{actor} convidou uma nova pessoa para cuidar da máquina.", actor: actor_label(event))
    else
      gettext("%{actor} convidou uma nova pessoa para a comunidade.", actor: actor_label(event))
    end
  end

  # O papel do convite, gravado no aceite, decide a frase: quem entra para
  # cuidar da máquina merece a frase certa na hora da concessão. Eventos
  # antigos (payload vazio) caem na frase genérica.
  defp sentence(%Event{type: :invite_accepted, payload: %{"role" => "zelador"}} = event),
    do: gettext("%{actor} entrou na comunidade para cuidar da máquina.", actor: actor_label(event))

  defp sentence(%Event{type: :invite_accepted} = event),
    do: gettext("%{actor} entrou na comunidade.", actor: actor_label(event))

  defp sentence(%Event{type: :invite_revoked, payload: %{"role" => "zelador"}} = event),
    do: gettext("%{actor} revogou um convite para cuidar da máquina.", actor: actor_label(event))

  defp sentence(%Event{type: :invite_revoked} = event),
    do: gettext("%{actor} revogou um convite.", actor: actor_label(event))

  # O zelador não vê nem define a senha nova, só gera o link: o ato é dele,
  # o destino é o membro nomeado no payload.
  defp sentence(%Event{type: :reset_link_created, payload: %{"member" => member}} = event) when is_binary(member),
    do: gettext("%{actor} gerou um link de nova senha para %{member}.", actor: actor_label(event), member: member)

  defp sentence(%Event{type: :reset_link_created} = event),
    do: gettext("%{actor} gerou um link de nova senha para um membro da comunidade.", actor: actor_label(event))

  defp sentence(%Event{type: :member_deactivated} = event) do
    case event.payload["member"] do
      nil -> gettext("%{actor} desativou uma conta.", actor: actor_label(event))
      member -> gettext("%{actor} desativou a conta de %{member}.", actor: actor_label(event), member: member)
    end
  end

  # Papel do membro depois da mudança: ganhou o cuidado ("deu a") ou voltou a
  # ser morador ("tirou de"). Sem nome/papel no payload, frase genérica.
  defp sentence(%Event{type: :member_role_changed, payload: %{"member" => member, "role" => "zelador"}} = event)
       when is_binary(member) do
    gettext("%{actor} deu a %{member} o cuidado da máquina.", actor: actor_label(event), member: member)
  end

  defp sentence(%Event{type: :member_role_changed, payload: %{"member" => member, "role" => "morador"}} = event)
       when is_binary(member) do
    gettext("%{actor} tirou de %{member} o cuidado da máquina.", actor: actor_label(event), member: member)
  end

  defp sentence(%Event{type: :member_role_changed} = event),
    do: gettext("%{actor} mudou o papel de um membro da comunidade.", actor: actor_label(event))

  defp sentence(%Event{type: :member_reactivated, payload: %{"member" => member}} = event) when is_binary(member),
    do: gettext("%{actor} reativou a conta de %{member}.", actor: actor_label(event), member: member)

  defp sentence(%Event{type: :member_reactivated} = event),
    do: gettext("%{actor} reativou uma conta.", actor: actor_label(event))

  defp sentence(%Event{type: :published_to_praca, payload: %{"kind" => "folder", "name" => name}} = event),
    do: gettext("%{actor} publicou a pasta \"%{name}\" na praça.", actor: actor_label(event), name: name)

  defp sentence(%Event{type: :published_to_praca, payload: %{"name" => name}} = event),
    do: gettext("%{actor} publicou o arquivo \"%{name}\" na praça.", actor: actor_label(event), name: name)

  defp sentence(%Event{type: :published_to_praca} = event),
    do: gettext("%{actor} publicou um arquivo na praça.", actor: actor_label(event))

  defp sentence(%Event{type: :moved_between_zones, payload: %{"kind" => "folder", "name" => name}} = event),
    do: gettext("%{actor} tirou a pasta \"%{name}\" da praça.", actor: actor_label(event), name: name)

  defp sentence(%Event{type: :moved_between_zones, payload: %{"name" => name}} = event),
    do: gettext("%{actor} tirou o arquivo \"%{name}\" da praça.", actor: actor_label(event), name: name)

  defp sentence(%Event{type: :moved_between_zones} = event),
    do: gettext("%{actor} tirou um arquivo da praça.", actor: actor_label(event))

  defp sentence(%Event{type: :access_requested, payload: %{"owner" => owner}} = event),
    do: gettext("%{actor} pediu acesso à casa de %{owner}.", actor: actor_label(event), owner: owner)

  defp sentence(%Event{type: :access_requested} = event),
    do: gettext("%{actor} pediu acesso a uma casa.", actor: actor_label(event))

  defp sentence(%Event{type: :access_granted, payload: %{"requester" => requester}} = event),
    do: gettext("%{actor} aprovou o pedido de acesso de %{requester}.", actor: actor_label(event), requester: requester)

  defp sentence(%Event{type: :access_granted} = event),
    do: gettext("%{actor} aprovou um pedido de acesso.", actor: actor_label(event))

  defp sentence(%Event{type: :access_denied, payload: %{"requester" => requester}} = event),
    do: gettext("%{actor} recusou o pedido de acesso de %{requester}.", actor: actor_label(event), requester: requester)

  defp sentence(%Event{type: :access_denied} = event),
    do: gettext("%{actor} recusou um pedido de acesso.", actor: actor_label(event))

  defp sentence(%Event{type: :quota_changed, payload: %{"from" => from, "to" => to}} = event) when is_integer(from) do
    gettext("%{actor} mudou o limite de armazenamento de %{from} para %{to}.",
      actor: actor_label(event),
      from: format_bytes(from),
      to: format_bytes(to)
    )
  end

  defp sentence(%Event{type: :quota_changed, payload: %{"to" => to}} = event),
    do: gettext("%{actor} mudou o limite de armazenamento para %{to}.", actor: actor_label(event), to: format_bytes(to))

  defp sentence(%Event{type: :quota_changed} = event),
    do: gettext("%{actor} mudou o limite de armazenamento.", actor: actor_label(event))

  # Evento de um type que a tela ainda não conhece: o mural é append-only e
  # não pode derrubar por causa de uma frase faltando. A frase genérica
  # mantém a linha no ar e o log marca o type para alguém escrever a frase
  # dele (e telemetria acompanhar) sem perder o registro.
  defp sentence(%Event{type: type} = event) do
    Logger.warning("mural: evento sem frase mapeada", event_type: type, event_id: event.id)

    gettext("%{actor} fez um ato registrado na comunidade.", actor: actor_label(event))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:mural}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <div class="col gap-6 mx-auto w-full measure-wide">
        <div>
          <h1 class="type-h1 mb-2">{gettext("Mural")}</h1>
          <p class="type-body-sm text-muted">
            {gettext("O que aconteceu na comunidade. Cada linha registra um ato: ninguém edita, ninguém apaga.")}
          </p>
        </div>

        <div id="mural-events" phx-update="stream" class="col gap-5">
          <div :for={{dom_id, entry} <- @streams.events} id={dom_id} class="col gap-1">
            <p :if={entry.day_label} class="type-overline text-muted">{entry.day_label}</p>
            <p class="type-body text-secondary">{entry.sentence}</p>
            <p class="type-caption text-muted">{entry.ago}</p>
          </div>
        </div>

        <div :if={@next_offset} id="mural-load-more" phx-viewport-bottom="load-more" class="center py-4">
          <p class="type-caption text-muted">{gettext("Carregando mais...")}</p>
        </div>

        <.empty_state
          :if={@event_count == 0 and not @load_error}
          icon="mural"
          title={gettext("Nada aconteceu ainda")}
          hint={
            gettext(
              "Quando alguém convidar, publicar na praça ou pedir acesso, o registro aparece aqui. Ninguém edita e ninguém apaga: o mural é a memória do que aconteceu."
            )
          }
        />

        <.empty_state
          :if={@load_error}
          icon="alert"
          title={gettext("Não foi possível carregar")}
          hint={gettext("O mural não respondeu agora.")}
        >
          <.button variant="secondary" phx-click="retry">{gettext("Tentar de novo")}</.button>
        </.empty_state>
      </div>
    </Layouts.app>
    """
  end
end
