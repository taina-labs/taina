defmodule TainaWeb.MuralLive do
  @moduledoc """
  Mural (RFC_003 seção 6, camada 1): o livro-caixa do "quem fez o quê", em
  frases simples, do mais recente para o mais antigo.

  Boards do Penpot (docs/web-revamp-spec.md 6.4): `padrao`
  cc1037dc-e8ab-80cc-8008-d5e174072f2d, `vazio` cc1037dc-e8ab-80cc-8008-d5e180cf1e7b,
  `degradado` cc1037dc-e8ab-80cc-8008-d5e182fef3eb e as versões Web
  cc1037dc-e8ab-80cc-8008-d5ead738a174 / Web 768
  cc1037dc-e8ab-80cc-8008-d5eaf0ed92e3.

  Somente leitura para todos os papéis, zelador(a) incluso: o mural é registro
  do que aconteceu, não é um lugar de agir, então não há filtro nem controle
  que sugira poder sobre o registro. Cada linha leva a frase no título e o
  próprio dia no meta ("Hoje, 09:12", board), sem cabeçalho de dia; quando
  não há mais páginas, o "Fim do mural." assume o lugar da sentinela (a lista
  acaba, sem spinner eterno). Os eventos chegam paginados por offset
  (`Maraca.list_events/2`) e as frases saem do `TainaWeb.MuralText`, o mesmo
  núcleo que alimenta a linha "Mural" do hub.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Ybira
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
          entries = load_page_entries(socket.assigns.current_scope, events)

          {:noreply,
           socket
           |> assign(:next_offset, next)
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

  # "Falar com quem cuida" (cartão de erro do board `degradado`): a Saúde é a
  # tela que diz quem cuida da máquina. Web não abre conversa com ninguém.
  def handle_event("contact", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/saude")}
  end

  # Carrega a primeira página sem derrubar a tela: se o mural falhar, o
  # cartão de erro do board `degradado` assume o lugar (sem flash duplicado).
  # O stream nasce vazio mesmo no erro: o corpo nunca lê assign que não existe.
  defp assign_events(socket) do
    case Maraca.list_events(socket.assigns.current_scope) do
      {:ok, %{events: events, next_offset: next}} ->
        entries = load_page_entries(socket.assigns.current_scope, events)

        socket
        |> assign(:next_offset, next)
        |> assign(:event_count, socket.assigns.event_count + length(entries))
        |> assign(:load_error, false)
        |> stream(:events, entries, reset: true)

      {:error, _reason} ->
        socket
        |> assign(:load_error, true)
        |> stream(:events, [])
    end
  end

  # --- core puro: dados -> dados ---

  # Modela a página para o render: frase pronta e o meta do board ("Hoje,
  # 09:12"). Datas no horário da comunidade (o banco grava em UTC; o dia de
  # quem lê não é o dia do banco).
  defp load_page_entries(scope, events) do
    actor_ids = events |> Enum.map(& &1.payload["actor"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    names =
      case Maraca.mural_actor_names(scope, actor_ids) do
        {:ok, names} -> names
        {:error, _reason} -> %{}
      end

    resources =
      case Ybira.public_resource_names(scope, MuralText.resource_refs(events)) do
        {:ok, resources} -> resources
        {:error, _reason} -> %{}
      end

    page_entries(events, %{actors: names, resources: resources})
  end

  defp page_entries(events, names) do
    Enum.map(events, &entry(&1, names))
  end

  defp entry(%Entry{} = event, names) do
    # A linha do board não fecha com ponto (o hub enxuga a mesma frase).
    sentence = event |> MuralText.sentence(names) |> String.trim_trailing(".")

    %{id: event.id, sentence: sentence, meta: entry_meta(event.inserted_at)}
  end

  # O dia no meta: "Hoje", "Ontem" e "Antes de ontem" (board); mais velho que
  # isso, a data por extenso, o mesmo falar que o mural já usava para os
  # grupos de dia.
  defp entry_meta(at) do
    day_label =
      case Date.diff(Time.local_today(), Time.local_date(at)) do
        0 -> gettext("Hoje")
        1 -> gettext("Ontem")
        2 -> gettext("Antes de ontem")
        _days -> Calendar.strftime(Time.local_date(at), "%d/%m/%Y")
      end

    day_label <> ", " <> Time.local_clock(at)
  end

  # --- shell imperativo: assign/render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/"}>
      <.mural_body
        load_error={@load_error}
        entries={@streams.events}
        event_count={@event_count}
        next_offset={@next_offset}
        more_error={@more_error}
      />
    </Layouts.page>
    """
  end

  @doc """
  Corpo do mural: componente puro, recebe a página carregada e devolve HEEx.
  É aqui que a tela escolhe entre cartão de erro (board `degradado`, com o
  esqueleto no lugar das linhas), lista (board `padrao`), vazio (board
  `vazio`) e o fim da lista ("Fim do mural.").
  """
  attr :load_error, :boolean, required: true
  attr :entries, :list, required: true, doc: "itens do stream: {dom_id, entry}"
  attr :event_count, :integer, required: true
  attr :next_offset, :integer, default: nil, doc: "nil = a lista acabou: o Fim do mural. assume a sentinela"
  attr :more_error, :boolean, required: true

  def mural_body(assigns) do
    ~H"""
    <div class="col gap-5">
      <.error_card
        :if={@load_error}
        title={gettext("Não conseguimos falar com a nuvem agora.")}
        retry_event="retry"
        contact_event="contact"
      />
      <.skeleton :if={@load_error} kind="list_row" count={3} />

      <ul :if={not @load_error} id="mural-events" phx-update="stream" class="list">
        <.list_row
          :for={{dom_id, entry} <- @entries}
          id={dom_id}
          kind="mural"
          title={entry.sentence}
          meta={entry.meta}
        >
          <:leading><.service_square mark="mural" /></:leading>
        </.list_row>
      </ul>

      <.empty_state
        :if={not @load_error and @event_count == 0}
        icon="folder"
        title={gettext("Nada no mural ainda")}
        body={
          gettext(
            "Ainda não aconteceu nada por aqui. Quando alguém publicar na praça ou cuidar da máquina, aparece neste mural."
          )
        }
      />

      <div :if={@next_offset} id="mural-load-more" class="col gap-2 center py-4">
        <div :if={@more_error} class="col gap-2 center">
          <p class="type-caption text-muted">{gettext("Não foi possível carregar mais do mural.")}</p>
          <.button kind="secondary" size="sm" phx-click="load-more">{gettext("Tentar de novo")}</.button>
        </div>
        <p :if={!@more_error} phx-viewport-bottom="load-more" class="type-caption text-muted">
          {gettext("Carregando mais...")}
        </p>
      </div>

      <p :if={@event_count > 0 and is_nil(@next_offset)} class="type-caption text-muted text-center">
        {gettext("Fim do mural.")}
      </p>
    </div>
    """
  end
end
