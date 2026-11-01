defmodule TainaWeb.HomeLive do
  @moduledoc """
  Hub (`/`): a porta de entrada da comunidade. Board "Hub / Inicio" do Penpot
  (docs/web-revamp-spec.md 6.1): `padrao` cc1037dc-e8ab-80cc-8008-d5e0476dc036,
  `com pedido` cc1037dc-e8ab-80cc-8008-d5e0ffd2c8bc, `recentes vazio`
  cc1037dc-e8ab-80cc-8008-d5e104375411 e `degradado`
  cc1037dc-e8ab-80cc-8008-d5e108b0f775.

  Ordem do board: cabeçalho (saudação, nome da comunidade, avatar), CareLine
  quando há pedido esperando, Serviços, Da comunidade (Mural, Saúde,
  Moradores), Espaço da comunidade e Recentes. Sem barra de navegação global:
  o hub é a única porta (spec 1.5). A lista de Recentes é viva e para em
  quatro itens (nota do board).

  Cada bloco que depende da nuvem carrega e degrada sozinho (`load_hub/1`):
  quando algum falha, o cartão de erro no topo explica e as seções afetadas
  viram esqueleto, nunca somem em silêncio (nota do board `degradado`).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Nhaman.Backup
  alias Taina.Ybira
  alias TainaWeb.Layouts
  alias TainaWeb.MuralText
  alias TainaWeb.Saude
  alias TainaWeb.Time

  # A lista de Recentes é limitada a 4 itens (nota do board do hub).
  @recent_limit 4

  @impl true
  def mount(_params, _session, socket) do
    # A tela carrega os próprios dados: nenhuma casca entrega estatística que
    # a tela não renderiza.
    {:ok,
     socket
     |> assign(:page_title, gettext("Início"))
     |> assign(:hub, load_hub(socket.assigns.current_scope))}
  end

  @impl true
  def handle_event("retry", _params, socket) do
    {:noreply, assign(socket, :hub, load_hub(socket.assigns.current_scope))}
  end

  # "Falar com quem cuida" (segunda saída do cartão de erro): a Saúde é a tela
  # que diz quem cuida da máquina. Web não abre conversa com ninguém.
  def handle_event("contact", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/saude")}
  end

  # O shell inscreve o morador nos eventos do Ava; o hub não reage a eles (o
  # CareLine se refaz no próximo mount), mas precisa ignorar o que não trata.
  @impl true
  def handle_info(_message, socket), do: {:noreply, socket}

  # --- core puro: dados -> dados ---

  # Uma leitura por bloco: `%{care:, community:, storage:, recent:}`, cada uma
  # `{:ok, dados} | {:error, motivo}`. O bloco que falha não derruba os outros.
  defp load_hub(scope) do
    storage = Ybira.storage_stats(scope)

    %{
      care: load_care(scope),
      community: load_community(scope, storage),
      storage: storage,
      recent: load_recent(scope)
    }
  end

  # "Carla pediu para abrir um arquivo da sua casa" (board `com pedido`).
  # Só os pedidos recebidos pedem resposta; sem pedido, a linha não existe.
  defp load_care(scope) do
    case Maraca.pedidos_recebidos(scope) do
      {:ok, []} -> {:ok, nil}
      {:ok, [pedido | _] = pedidos} -> {:ok, care_text(pedido, length(pedidos))}
      {:error, reason} -> {:error, reason}
    end
  end

  defp care_text(pedido, 1) do
    gettext("%{name} pediu para abrir %{what} da sua casa",
      name: person_name(pedido.pedinte),
      what: request_what(pedido.tipo)
    )
  end

  defp care_text(pedido, count) do
    gettext("%{name} e mais %{count} pediram para abrir itens da sua casa",
      name: person_name(pedido.pedinte),
      count: count - 1
    )
  end

  defp request_what("ypy.folder.v0"), do: gettext("uma pasta")
  defp request_what(_tipo), do: gettext("um arquivo")

  # "Da comunidade": as três linhas cívicas do board, com meta viva. O bloco
  # inteiro depende da nuvem, então falha inteiro.
  defp load_community(scope, storage_result) do
    with {:ok, storage} <- storage_result,
         {:ok, members} <- Maraca.list_members(scope),
         {:ok, %{events: events}} <- Maraca.list_events(scope, limit: 1) do
      {:ok, community_rows(members, events, storage)}
    end
  end

  defp community_rows(members, events, storage) do
    names = Map.new(members, &{&1.public_id, person_name(&1)})
    summary = Saude.summary_line(%{storage: storage, backup: Backup.last_backup()})

    [
      %{
        mark: "mural",
        title: gettext("Mural"),
        meta: mural_meta(events, names),
        path: ~p"/mural"
      },
      %{
        mark: "saude",
        title: gettext("Saúde da comunidade"),
        meta: summary.line,
        path: ~p"/saude"
      },
      %{
        mark: "moradores",
        title: gettext("Moradores"),
        meta: residents_meta(members),
        path: ~p"/moradores"
      }
    ]
  end

  # "Ana publicou um arquivo, hoje": a frase do último ato do mural, sem o
  # ponto final, com o dia relativo da comunidade.
  defp mural_meta([], _names), do: gettext("Nada aconteceu ainda")

  defp mural_meta([event | _rest], names) do
    sentence = event |> MuralText.sentence(names) |> String.trim_trailing(".")

    sentence <> ", " <> ago_label(event.inserted_at)
  end

  # Convites não aceitos e contas desativadas não são moradores da comunidade.
  defp residents_meta(members) do
    count = Enum.count(members, &active_member?/1)

    ngettext("1 pessoa na comunidade", "%{count} pessoas na comunidade", count)
  end

  defp active_member?(%{activated_at: activated_at, deactivated_at: deactivated_at}),
    do: not is_nil(activated_at) and is_nil(deactivated_at)

  defp load_recent(scope) do
    with {:ok, files} <- Ybira.list_recent(scope, limit: @recent_limit) do
      {:ok, Enum.map(files, &recent_row/1)}
    end
  end

  # O quadradinho da linha: foto leva o acento do Jaci, vídeo o do vídeo, o
  # resto o documento (a linha de arquivo do board do hub).
  defp recent_row(file) do
    %{
      mark: file_mark(file.mime),
      title: file.nome,
      meta: recent_meta(file),
      path: ~p"/documentos/#{file.rkey}"
    }
  end

  defp file_mark("image/" <> _rest), do: "jaci"
  defp file_mark("video/" <> _rest), do: "video"
  defp file_mark(_mime), do: "doc"

  # "PDF, 2,4 MB, hoje" (spec 1.6: metadados separados por vírgula).
  defp recent_meta(file) do
    [file_kind(file.mime), format_bytes(file.tamanho), ago_label(file.inserted_at)]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  # Dia relativo no horário da comunidade: o banco grava em UTC, o "hoje" é o
  # de quem lê.
  defp ago_label(at) do
    days = Date.diff(Time.local_today(), Time.local_date(at))

    cond do
      days <= 0 -> gettext("hoje")
      days == 1 -> gettext("ontem")
      days < 7 -> ngettext("há %{count} dia", "há %{count} dias", days)
      days < 14 -> gettext("há 1 semana")
      days < 30 -> ngettext("há %{count} semana", "há %{count} semanas", div(days, 7))
      days < 60 -> gettext("há 1 mês")
      true -> ngettext("há %{count} mês", "há %{count} meses", div(days, 30))
    end
  end

  # Saudação pelo relógio da caixa: o servidor mora na casa da comunidade,
  # então o horário local do sistema é o horário local de quem usa.
  defp greeting(name) do
    {_date, {hour, _min, _sec}} = :calendar.local_time()
    gettext("%{period}, %{name}", period: period(hour), name: name)
  end

  defp period(hour) when hour in 5..11, do: gettext("Bom dia")
  defp period(hour) when hour in 12..17, do: gettext("Boa tarde")
  defp period(_hour), do: gettext("Boa noite")

  defp person_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  defp person_name(%{username: name}) when is_binary(name), do: name
  defp person_name(_ava), do: ""

  # --- shell imperativo: assign/render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.hub flash={@flash}>
      <.hub_body hub={@hub} scope={@current_scope} />
    </Layouts.hub>
    """
  end

  @doc """
  Corpo do hub: componente puro, recebe os blocos carregados e o escopo e
  devolve HEEx. É aqui que cada bloco escolhe entre ok, vazio, esqueleto e
  cartão de erro (nenhum silêncio, spec 1.3).
  """
  attr :hub, :map, required: true
  attr :scope, :any, required: true

  def hub_body(assigns) do
    assigns =
      assigns
      |> assign(:greeting, greeting(person_name(assigns.scope.ava)))
      |> assign(:care_line_text, care_line_text(assigns.hub))
      |> assign(:community_rows, block_rows(assigns.hub.community))
      |> assign(:storage_stats, block_value(assigns.hub.storage))
      |> assign(:recent_rows, block_rows(assigns.hub.recent))
      |> assign(:degraded?, degraded?(assigns.hub))

    ~H"""
    <div class="col gap-6">
      <.hub_header greeting={@greeting} community={@scope.tekoa.name} user={@scope.ava}>
        <:care :if={@care_line_text}>
          <.care_line
            text={@care_line_text}
            action_label={gettext("Responder")}
            navigate={~p"/conta/pedidos"}
          />
        </:care>
      </.hub_header>

      <.error_card
        :if={@degraded?}
        title={gettext("Não conseguimos falar com a nuvem agora.")}
        retry_event="retry"
        contact_event="contact"
      />

      <section class="col gap-3">
        <h2 class="type-overline text-muted">{gettext("Serviços")}</h2>
        <div class="row gap-3">
          <div class="flex-1">
            <.service_card
              service="ybira"
              title={gettext("Documentos")}
              meta={gettext("Arquivos da casa e da praça")}
              navigate={~p"/documentos"}
            />
          </div>
          <div class="flex-1">
            <.service_card
              service="jaci"
              title={gettext("Galeria")}
              meta={gettext("Fotos da casa e da praça")}
              navigate={~p"/galeria"}
            />
          </div>
        </div>
      </section>

      <section class="col gap-3">
        <h2 class="type-overline text-muted">{gettext("Da comunidade")}</h2>
        <ul :if={@community_rows != nil} class="list">
          <.list_row
            :for={row <- @community_rows}
            kind="civic"
            trailing="chevron"
            title={row.title}
            meta={row.meta}
            navigate={row.path}
          >
            <:leading>
              <.service_square mark={row.mark} />
            </:leading>
          </.list_row>
        </ul>
        <.skeleton :if={is_nil(@community_rows)} kind="list_row" count={2} />
      </section>

      <.storage_card
        :if={@storage_stats}
        stats={@storage_stats}
        detail="compact"
        navigate={~p"/armazenamento"}
      />
      <.skeleton :if={is_nil(@storage_stats)} kind="card" count={1} />

      <section class="col gap-3">
        <h2 class="type-overline text-muted">{gettext("Recentes")}</h2>
        <ul :if={@recent_rows not in [nil, []]} class="list">
          <.list_row
            :for={row <- @recent_rows}
            kind="file"
            trailing="chevron"
            title={row.title}
            meta={row.meta}
            navigate={row.path}
          >
            <:leading>
              <.service_square mark={row.mark} />
            </:leading>
          </.list_row>
        </ul>
        <.empty_state
          :if={@recent_rows == []}
          icon="folder"
          title={gettext("Nada recente")}
          body={gettext("O que chegar de novo aparece aqui.")}
          tag="h3"
        />
        <.skeleton :if={is_nil(@recent_rows)} kind="list_row" count={2} />
      </section>
    </div>
    """
  end

  # O CareLine só existe com pedido esperando; bloco que falhou não inventa um
  # aviso que não sabe.
  defp care_line_text(%{care: {:ok, text}}), do: text
  defp care_line_text(_hub), do: nil

  defp block_rows({:ok, rows}), do: rows
  defp block_rows({:error, _reason}), do: nil

  defp block_value({:ok, value}), do: value
  defp block_value({:error, _reason}), do: nil

  # A nuvem não respondeu em algum bloco? O cartão de erro do board cobre a
  # falha; cada seção afetada mostra esqueleto (nunca um vazio mentiroso).
  defp degraded?(hub) do
    Enum.any?([hub.community, hub.storage, hub.recent], &match?({:error, _}, &1))
  end
end
