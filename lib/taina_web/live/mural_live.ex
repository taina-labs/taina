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

  import Ecto.Query

  alias Taina.Maraca
  alias TainaWeb.Layouts
  alias TainaWeb.MuralText
  alias TainaWeb.Time
  alias Ypy.Mural.Entry

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Mural"))
     |> assign(:next_offset, nil)
     |> assign(:headed_dates, MapSet.new())
     |> assign(:event_count, 0)
     |> assign(:load_error, false)
     |> assign(:more_error, false)
     |> assign_events()}
  end

  @impl true
  def handle_event("load-more", _params, socket) do
    if offset = socket.assigns.next_offset do
      case Maraca.list_events(socket.assigns.current_scope, offset: offset) do
        {:ok, %{events: events, next_offset: next}} ->
          {entries, headed} = page_entries(socket.assigns.current_scope, events, socket.assigns.headed_dates)

          {:noreply,
           socket
           |> assign(:next_offset, next)
           |> assign(:headed_dates, headed)
           |> assign(:event_count, socket.assigns.event_count + length(entries))
           |> assign(:more_error, false)
           |> stream(:events, entries)}

        # Paginação que falha não fica em silêncio nem presa no "Carregando
        # mais": o estado fica marcado e a sentinela dá lugar ao "Tentar de
        # novo" (o mesmo falar da primeira página).
        {:error, _reason} ->
          {:noreply, assign(socket, :more_error, true)}
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
        {entries, headed} = page_entries(socket.assigns.current_scope, events, socket.assigns.headed_dates)

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
  defp page_entries(scope, events, headed_dates) do
    names = actor_names(scope, events)

    Enum.map_reduce(events, headed_dates, fn event, headed ->
      date = Time.local_date(event.inserted_at)

      if MapSet.member?(headed, date) do
        {entry(event, names, nil), headed}
      else
        {entry(event, names, day_title(date)), MapSet.put(headed, date)}
      end
    end)
  end

  defp entry(%Entry{} = event, names, day_label) do
    %{
      id: event.id,
      day_label: day_label,
      sentence: MuralText.sentence(event, names),
      ago: ago_label(event.inserted_at)
    }
  end

  # O nome social do ator, resolvido da projecao: nome de exibição quando
  # existe, senão o nome de usuário. A cadeia guarda o public_id; a tela é
  # quem traduz para gente. Sem ator (ato do sistema), "O sistema".
  defp actor_names(%Ypy.Scope{} = scope, events) do
    pids = events |> Enum.map(& &1.payload["actor"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    {:ok, pairs} =
      Taina.Repo.with_tekoa(scope.tekoa.public_id, fn ->
        pairs =
          Taina.Repo.all(
            from(a in Ypy.Maraca.Ava,
              where: a.public_id in ^pids,
              select: {a.public_id, {a.display_name, a.username}}
            )
          )

        {:ok, pairs}
      end)

    Map.new(pairs, fn {pid, {display, username}} -> {pid, display || username} end)
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

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/"}>
      <div class="col gap-6 mx-auto w-full measure-wide">
        <p class="type-body-sm text-muted">
          {gettext("O que aconteceu na comunidade. Cada linha registra um ato: ninguém edita, ninguém apaga.")}
        </p>

        <div id="mural-events" phx-update="stream" class="col gap-5">
          <div :for={{dom_id, entry} <- @streams.events} id={dom_id} class="col gap-1">
            <p :if={entry.day_label} class="type-overline text-muted">{entry.day_label}</p>
            <p class="type-body text-secondary">{entry.sentence}</p>
            <p class="type-caption text-muted">{entry.ago}</p>
          </div>
        </div>

        <div :if={@next_offset} id="mural-load-more" class="col gap-2 center py-4">
          <p :if={!@more_error} phx-viewport-bottom="load-more" class="type-caption text-muted">
            {gettext("Carregando mais...")}
          </p>
          <div :if={@more_error} class="col gap-2 center">
            <p class="type-caption text-muted">{gettext("Não foi possível carregar mais do mural.")}</p>
            <.button variant="secondary" size="sm" phx-click="load-more">{gettext("Tentar de novo")}</.button>
          </div>
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
    </Layouts.page>
    """
  end
end
