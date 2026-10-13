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
  alias TainaWeb.Time
  alias Ypy.Mural.Entry

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
      sentence: sentence(event, names),
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

  defp actor_label(event, names) do
    Map.get(names, event.payload["actor"], gettext("O sistema"))
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

  # Frases do mural: cada `type` vira uma frase simples, sem IDs e sem jargão.
  # Se um ato não cabe numa frase, o problema é o `type`, não a frase.
  defp sentence(%Entry{tipo: "invite_created"} = event, names) do
    if event.payload["role"] == "zelador" do
      gettext("%{actor} convidou uma nova pessoa para cuidar da máquina.", actor: actor_label(event, names))
    else
      gettext("%{actor} convidou uma nova pessoa para a comunidade.", actor: actor_label(event, names))
    end
  end

  # O papel do convite, gravado no aceite, decide a frase: quem entra para
  # cuidar da máquina merece a frase certa na hora da concessão. Eventos
  # antigos (payload vazio) caem na frase genérica.
  defp sentence(%Entry{tipo: "invite_accepted", payload: %{"role" => "zelador"}} = event, names),
    do: gettext("%{actor} entrou na comunidade para cuidar da máquina.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "invite_accepted"} = event, names),
    do: gettext("%{actor} entrou na comunidade.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "invite_revoked", payload: %{"role" => "zelador"}} = event, names),
    do: gettext("%{actor} revogou um convite para cuidar da máquina.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "invite_revoked"} = event, names),
    do: gettext("%{actor} revogou um convite.", actor: actor_label(event, names))

  # O zelador não vê nem define a senha nova, só gera o link: o ato é dele,
  # o destino é o membro nomeado no payload.
  defp sentence(%Entry{tipo: "reset_link_created", payload: %{"member" => member}} = event, names) when is_binary(member),
    do: gettext("%{actor} gerou um link de nova senha para %{member}.", actor: actor_label(event, names), member: member)

  defp sentence(%Entry{tipo: "reset_link_created"} = event, names),
    do: gettext("%{actor} gerou um link de nova senha para um membro da comunidade.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "member_deactivated"} = event, names) do
    case event.payload["member"] do
      nil -> gettext("%{actor} desativou uma conta.", actor: actor_label(event, names))
      member -> gettext("%{actor} desativou a conta de %{member}.", actor: actor_label(event, names), member: member)
    end
  end

  defp sentence(%Entry{tipo: "member_reactivated", payload: %{"member" => member}} = event, names) when is_binary(member),
    do: gettext("%{actor} reativou a conta de %{member}.", actor: actor_label(event, names), member: member)

  defp sentence(%Entry{tipo: "member_reactivated"} = event, names),
    do: gettext("%{actor} reativou uma conta.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "quota_changed", payload: %{"from" => from, "to" => to}} = event, names)
       when is_integer(from) do
    gettext("%{actor} mudou o limite de armazenamento de %{from} para %{to}.",
      actor: actor_label(event, names),
      from: format_bytes(from),
      to: format_bytes(to)
    )
  end

  defp sentence(%Entry{tipo: "quota_changed", payload: %{"to" => to}} = event, names),
    do:
      gettext("%{actor} mudou o limite de armazenamento para %{to}.",
        actor: actor_label(event, names),
        to: format_bytes(to)
      )

  defp sentence(%Entry{tipo: "quota_changed"} = event, names),
    do: gettext("%{actor} mudou o limite de armazenamento.", actor: actor_label(event, names))

  # Verbos do kernel na cadeia: o payload deles carrega o ator e a coleção
  # (o rkey do recurso fica no payload para a auditoria, não para a frase),
  # então a frase nomeia quem fez e o que fez, sem o nome do recurso.
  defp sentence(%Entry{tipo: "put", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} criou uma pasta.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "put"} = event, names),
    do: gettext("%{actor} guardou um arquivo na caixa.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "publicar", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} publicou uma pasta na praça.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "publicar"} = event, names),
    do: gettext("%{actor} publicou um arquivo na praça.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "tirar_da_praca", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} tirou uma pasta da praça.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "tirar_da_praca"} = event, names),
    do: gettext("%{actor} tirou um arquivo da praça.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "apagar", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} mandou uma pasta para a lixeira.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "apagar"} = event, names),
    do: gettext("%{actor} mandou um arquivo para a lixeira.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "restaurar"} = event, names),
    do: gettext("%{actor} tirou um arquivo da lixeira.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "mover"} = event, names),
    do: gettext("%{actor} moveu um arquivo de pasta.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "renomear", payload: %{"collection" => "ypy.folder.v0"}} = event, names),
    do: gettext("%{actor} renomeou uma pasta.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "renomear"} = event, names),
    do: gettext("%{actor} renomeou um arquivo.", actor: actor_label(event, names))

  # A concessao nasce de um pedido aprovado ou do proprio dono abrindo a
  # casa; o "leitor" (public_id) no payload para a auditoria.
  defp sentence(%Entry{tipo: "concessao"} = event, names),
    do: gettext("%{actor} abriu a sua casa para a leitura de um morador.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "revogar"} = event, names),
    do: gettext("%{actor} tirou a leitura que tinha aberto.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "mudar_papel", payload: %{"papel" => "zelador"}} = event, names),
    do: gettext("%{actor} deu a um morador o cuidado da máquina.", actor: actor_label(event, names))

  defp sentence(%Entry{tipo: "mudar_papel"} = event, names),
    do: gettext("%{actor} tirou de um morador o cuidado da máquina.", actor: actor_label(event, names))

  # Entrada de um tipo que a tela ainda não conhece (inclui os tipos do
  # kernel: concessao, publicar, put...): o mural e append-only e nao pode
  # derrubar por causa de uma frase faltando. A frase genérica mantém a linha
  # no ar e o log marca o tipo para alguém escrever a frase dele.
  defp sentence(%Entry{tipo: tipo} = event, names) do
    Logger.warning("mural: entrada sem frase mapeada", event_type: tipo, event_id: event.id)

    gettext("%{actor} fez um ato registrado na comunidade.", actor: actor_label(event, names))
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
    </Layouts.app>
    """
  end
end
