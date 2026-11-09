defmodule TainaWeb.AccessRequestsLive do
  @moduledoc """
  Pedidos ("Conta -> Pedidos", RFC_003 D4; spec 6.4, boards "Pedidos" do
  Penpot): `com pedidos` cc1037dc-e8ab-80cc-8008-d5e227df15d9, `vazio`
  cc1037dc-e8ab-80cc-8008-d5e22b5109c1 e `enviado`
  cc1037dc-e8ab-80cc-8008-d62898a2525a.

  A fila de quem recebe o pedido, nos três estados do board: pendente ("Carla
  pediu acesso" com Recusar e Dar acesso na linha), concedido ("João recebeu
  acesso", com o dia) e recusado ("Marina teve o acesso recusado"). Um pedido
  decidido não desaparece (RFC_003: sem resultado silencioso) e o concedido
  continua reversível na linha ("Tirar acesso"): o rodapé do board promete
  "Você pode mudar de ideia quando quiser".

  Quem pediu vê o estado `enviado` enquanto a resposta não vem ("Ana vai
  decidir. Você vê a resposta aqui em Pedidos."). O pedido em si sai da
  pré-visualização do arquivo; a resposta chega por aqui e por aviso no hub.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts
  alias TainaWeb.Time

  @impl true
  def mount(_params, _session, socket) do
    # A inscrição no tópico do Ava já acontece no shell (`TainaWeb.Hooks`);
    # inscrever de novo entrega cada evento duas vezes.
    {:ok,
     socket
     |> assign(:page_title, gettext("Pedidos"))
     |> assign(:confirm_deny, nil)
     |> assign(:confirm_revoke, nil)
     |> assign_requests()}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    pedido = Enum.find(socket.assigns.requests, &("#{&1.id}" == id))
    message = approved_message(socket.assigns.resource_names, pedido)

    case pedido && Maraca.aprovar(socket.assigns.current_scope, pedido) do
      {:ok, _concessao} ->
        {:noreply,
         socket
         |> assign_requests()
         |> Phoenix.LiveView.put_flash(:info, message)}

      result when result in [nil, {:error, :not_authorized}, {:error, :not_pending}, {:error, :not_found}] ->
        {:noreply, socket |> assign_requests() |> decision_gone()}

      {:error, _reason} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Este pedido já foi resolvido."))}
    end
  end

  def handle_event("ask-deny", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_deny, id)}
  end

  def handle_event("ask-revoke", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_revoke, id)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, socket |> assign(:confirm_deny, nil) |> assign(:confirm_revoke, nil)}
  end

  def handle_event("deny", %{"id" => id}, socket) do
    pedido = Enum.find(socket.assigns.requests, &("#{&1.id}" == id))

    case pedido && Maraca.negar(socket.assigns.current_scope, pedido) do
      {:ok, _pedido} ->
        {:noreply,
         socket
         |> assign(:confirm_deny, nil)
         |> assign_requests()
         |> Phoenix.LiveView.put_flash(:info, gettext("Pedido negado."))}

      result when result in [nil, {:error, :not_authorized}, {:error, :not_pending}, {:error, :not_found}] ->
        {:noreply,
         socket
         |> assign(:confirm_deny, nil)
         |> assign_requests()
         |> decision_gone()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:confirm_deny, nil)
         |> Phoenix.LiveView.put_flash(:error, gettext("Este pedido já foi resolvido."))}
    end
  end

  # Acesso que sumiu entre abrir a confirmação e confirmar (outra aba tirou
  # primeiro, ou o pedido já não existe mais): recarrega em vez de culpar
  # ninguém, a lista volta certa.
  def handle_event("revoke", _params, socket) do
    concessao = find_grant(socket.assigns.grants, socket.assigns.confirm_revoke)

    case concessao && Maraca.revogar(socket.assigns.current_scope, concessao) do
      {:ok, _concessao} ->
        {:noreply,
         socket
         |> assign(:confirm_revoke, nil)
         |> assign_requests()
         |> Phoenix.LiveView.put_flash(:info, revoked_message(concessao))}

      result when result in [nil, {:error, :not_authorized}, {:error, :invalid_status}, {:error, :not_found}] ->
        {:noreply, access_gone(socket)}

      _error ->
        {:noreply,
         socket
         |> assign(:confirm_revoke, nil)
         |> Phoenix.LiveView.put_flash(
           :error,
           gettext("Não foi possível tirar o acesso agora. Tente de novo.")
         )}
    end
  end

  def handle_event("retry-grants", _params, socket), do: {:noreply, assign_requests(socket)}

  defp access_gone(socket) do
    socket
    |> assign(:confirm_revoke, nil)
    |> assign_requests()
    |> Phoenix.LiveView.put_flash(:error, gettext("Este acesso já foi tirado."))
  end

  @impl true
  def handle_info({:access_requested, _request}, socket) do
    {:noreply, assign_requests(socket)}
  end

  def handle_info({:access_request_approved, concessao}, socket) do
    message = outgoing_approved_message(socket.assigns.resource_names, concessao.tipo, concessao.recurso)

    {:noreply,
     socket
     |> assign_requests()
     |> Phoenix.LiveView.put_flash(:info, message)}
  end

  def handle_info({:access_request_denied, _request}, socket) do
    {:noreply,
     socket
     |> assign_requests()
     |> Phoenix.LiveView.put_flash(:info, gettext("Seu pedido foi negado."))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- shell imperativo: assign/put_flash ---

  defp assign_requests(socket) do
    scope = socket.assigns.current_scope
    {:ok, requests} = Maraca.pedidos_recebidos(scope)
    {:ok, outgoing} = Maraca.pedidos_enviados(scope)
    {:ok, decisions} = Maraca.list_my_recent_decisions(scope)
    {:ok, refusals} = Maraca.list_owner_recent_refusals(scope)
    resource_requests = requests ++ outgoing ++ decisions ++ refusals

    socket
    |> assign(:requests, requests)
    |> assign(:outgoing, outgoing)
    |> assign(:decisions, decisions)
    |> assign(:refusals, refusals)
    |> assign_grants(resource_requests)
  end

  # A seção concedida ("João recebeu acesso", board) carrega por último e
  # decai sozinha: se falhar, o resto da tela continua no ar, com o estado de
  # erro (e a saída) só nela.
  defp assign_grants(socket, resource_requests) do
    scope = socket.assigns.current_scope

    {grants, grants_error} =
      case load_grants(scope) do
        {:ok, grants} -> {grants, false}
        {:error, _reason} -> {[], true}
      end

    resource_names =
      case Maraca.access_resource_names(scope, resource_requests, grants) do
        {:ok, names} -> names
        {:error, _reason} -> %{}
      end

    socket
    |> assign(:grants, grants)
    |> assign(:resource_names, resource_names)
    |> assign(:grants_error, grants_error)
  end

  # O Maraca devolve `{:ok, lista}` (e `{:error, motivo}` em falha de banco);
  # a borda da tela degrada para o estado de erro da seção, sem exceção.
  defp load_grants(scope), do: Maraca.concessoes_concedidas(scope)

  # Pedido resolvido entre o render e o clique (decidido em outra aba): some a
  # linha sem mensagem de erro tecnica.
  defp decision_gone(socket) do
    Phoenix.LiveView.put_flash(socket, :error, gettext("Este pedido já foi resolvido."))
  end

  # --- core puro: dados -> dados ---

  # O estado do board é função pura do que há em cada lado (spec 1.3):
  #   * nada em lugar nenhum: `vazio` ("Nenhum pedido ainda");
  #   * quem pediu esperando resposta, sem fila para decidir: `enviado`
  #     ("Pedido enviado");
  #   * o resto: `com` (a fila do board, pendente e decidido). A seção
  #     concedida que falhou também conta: erro nunca vira vazio mentiroso.
  defp board_state(assigns) do
    cond do
      assigns.grants_error -> :com_pedidos
      nothing_here?(assigns) and assigns.outgoing == [] -> :vazio
      nothing_here?(assigns) -> :enviado
      true -> :com_pedidos
    end
  end

  # A fila do dono (o que há para decidir ou já foi decidido) está vazia.
  defp nothing_here?(assigns) do
    assigns.requests == [] and assigns.grants == [] and assigns.decisions == [] and assigns.refusals == []
  end

  # --- core puro: dados -> dados ---
  # (decidido em `board_state/1` abaixo: o estado do board é função pura do
  # que há em cada lado)

  defp requester_name(request) do
    request.pedinte.display_name || request.pedinte.username
  end

  defp owner_name(request) do
    request.dono.display_name || request.dono.username
  end

  defp recipient_name(concessao) do
    concessao.leitor.display_name || concessao.leitor.username
  end

  defp resource_display_name(names, resource) do
    case Map.fetch(names, {resource.tipo, resource.recurso}) do
      {:ok, name} -> name
      :error -> deleted_resource_label(resource.tipo)
    end
  end

  defp deleted_resource_label("ypy.folder.v0"), do: gettext("pasta apagada")
  defp deleted_resource_label(_kind), do: gettext("arquivo apagado")

  # "doc.txt, hoje 09:12" (board: metadados separados por vírgula, o relógio
  # da comunidade).
  defp row_meta(names, resource) do
    Enum.join([resource_display_name(names, resource), day_clock(acted_at(resource))], ", ")
  end

  # Pedido tem o instante no `inserted_at`; concessão, no `concedida_em`.
  defp acted_at(%{concedida_em: at}) when not is_nil(at), do: at
  defp acted_at(%{inserted_at: at}), do: at

  # "hoje 09:12" / "ontem 18:20" (board); mais velho que isso, o relativo do
  # design system.
  defp day_clock(at) do
    case Date.diff(Time.local_today(), Time.local_date(at)) do
      0 -> gettext("hoje") <> " " <> Time.local_clock(at)
      1 -> gettext("ontem") <> " " <> Time.local_clock(at)
      _days -> relative_time(at)
    end
  end

  # "23 out" (board): dia e mês curto da comunidade (o strftime do Elixir não
  # fala pt-BR, então o mês curto é da tela).
  defp day_label(at) do
    date = Time.local_date(at)
    months = ~w(jan fev mar abr mai jun jul ago set out nov dez)

    "#{date.day} #{Enum.at(months, date.month - 1)}"
  end

  defp find_grant(grants, id) when is_binary(id) do
    Enum.find(grants, &("#{&1.id}" == id))
  end

  defp find_grant(_grants, nil), do: nil

  defp revoke_title(grants, id) do
    case find_grant(grants, id) do
      nil -> gettext("Tirar este acesso?")
      grant -> gettext("Tirar o acesso de %{name}?", name: recipient_name(grant))
    end
  end

  defp revoked_message(grant) do
    gettext("Acesso de %{name} tirado.", name: recipient_name(grant))
  end

  # Flash da aprovação nomeia o arquivo: a decisão é sobre aquele arquivo, não
  # sobre "um pedido".
  defp approved_message(names, pedido) do
    case pedido && Map.get(names, {pedido.tipo, pedido.recurso}) do
      file when is_binary(file) -> gettext("Acesso a %{file} liberado. A pessoa já pode ler.", file: file)
      _other -> gettext("Acesso liberado. A pessoa já pode ler.")
    end
  end

  # Aprovação chegando pelo PubSub nomeia o arquivo quando o nome já está na
  # tela (pedido que veio depois do mount deixa o flash genérico).
  defp outgoing_approved_message(names, kind, rkey) do
    case Map.get(names, {kind, rkey}) do
      file when is_binary(file) -> gettext("Pedido aprovado: agora você pode abrir %{file}.", file: file)
      _other -> gettext("Seu pedido foi aprovado. Você já pode abrir.")
    end
  end

  # O motivo vem na sequência do meta e a linha quebra em vez de cortar com
  # reticências (`list-row__meta--wrap` no render): decidir sem ler o porquê
  # é decidir às cegas.
  defp request_meta(request, names) do
    base = row_meta(names, request)

    case request.motivo do
      nil -> base
      reason -> base <> " " <> gettext("Motivo: %{reason}", reason: reason)
    end
  end

  # As linhas decididas do board (spec 1.3; a composição mora aqui para o
  # render ficar plano). São dois lados:
  #
  #   * o que EU concedi (dono): "Maria recebeu acesso", com o dia pendurado
  #     na linha (ícone + palavra; nunca só a cor, spec 1.7) e o Tirar acesso;
  #   * a resposta para os pedidos que EU mandei (quem pediu): o verbo é do
  #     dono ("Joana liberou o acesso" / "Joana recusou o pedido"), o
  #     compromisso do board `enviado` ("você vê a resposta aqui").
  defp granted_rows(grants, names) do
    Enum.map(grants, fn grant ->
      %{
        id: grant.id,
        state: "dado",
        title: gettext("%{name} recebeu acesso", name: recipient_name(grant)),
        meta: row_meta(names, grant),
        status_state: "ok",
        status: gettext("Acesso dado em %{date}", date: day_label(grant.concedida_em)),
        revocable: true
      }
    end)
  end

  defp decided_sent_rows(decisions, names) do
    Enum.map(decisions, fn decision ->
      %{
        id: decision.id,
        state: decision_state(decision.status),
        title: decision_title(decision),
        meta: row_meta(names, decision),
        status_state: nil,
        status: nil,
        revocable: false
      }
    end)
  end

  # A recusa que EU dei (dono): o board mostra a linha e o dia, sem ação -
  # a pessoa pode pedir de novo, e o rito fica visível.
  defp refused_rows(refusals, names) do
    Enum.map(refusals, fn refusal ->
      %{
        id: refusal.id,
        state: "recusado",
        title: gettext("%{name} teve o acesso recusado", name: requester_name(refusal)),
        meta: row_meta(names, refusal),
        status_state: "unknown",
        status: gettext("Acesso recusado em %{date}", date: day_label(refusal.decidido_em)),
        revocable: false
      }
    end)
  end

  defp decision_state(:aprovado), do: "dado"
  defp decision_state(:negado), do: "recusado"

  defp decision_title(%{status: :aprovado} = decision) do
    gettext("%{name} liberou o acesso", name: owner_name(decision))
  end

  defp decision_title(%{status: :negado} = decision) do
    gettext("%{name} recusou o pedido", name: owner_name(decision))
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:state, board_state(assigns))
      |> assign(:decided_grants, granted_rows(assigns.grants, assigns.resource_names))
      |> assign(
        :decided_sent,
        decided_sent_rows(assigns.decisions, assigns.resource_names)
      )
      |> assign(:decided_refused, refused_rows(assigns.refusals, assigns.resource_names))

    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/conta"} back_label={back_label("Conta")}>
      <div class="col gap-6">
        <.empty_state
          :if={@state == :vazio}
          icon="folder"
          title={gettext("Nenhum pedido ainda")}
          body={gettext("Quando alguém pedir para abrir um arquivo da sua casa, aparece aqui.")}
          tag="h2"
        />

        <.empty_state
          :if={@state == :enviado}
          icon="folder"
          title={gettext("Pedido enviado")}
          body={
            gettext(
              "%{name} vai decidir. Você vê a resposta aqui em Pedidos.",
              name: @outgoing |> List.first() |> owner_name()
            )
          }
          tag="h2"
        />

        <div :if={@state == :com_pedidos} class="col gap-4">
          <ul class="list">
            <.list_row
              :for={request <- @requests}
              kind="pedido"
              state="esperando"
              trailing="action"
              title={gettext("%{name} pediu acesso", name: requester_name(request))}
              meta={request_meta(request, @resource_names)}
              meta_class="list-row__meta--wrap"
            >
              <:leading>
                <.service_square mark="pedidos" tone="service" />
              </:leading>
              <:actions>
                <.button kind="secondary" size="sm" phx-click="ask-deny" phx-value-id={request.id}>
                  {gettext("Recusar")}
                </.button>
                <.button kind="primary" size="sm" phx-click="approve" phx-value-id={request.id}>
                  {gettext("Dar acesso")}
                </.button>
              </:actions>
            </.list_row>

            <li :for={row <- @decided_grants} class="col">
              <.list_row tag="div" kind="pedido" state={row.state} title={row.title} meta={row.meta}>
                <:leading>
                  <.service_square mark="pedidos" tone="service" />
                </:leading>
                <:actions>
                  <.button kind="ghost" size="sm" phx-click="ask-revoke" phx-value-id={row.id}>
                    {gettext("Tirar acesso")}
                  </.button>
                </:actions>
              </.list_row>
              <div class="px-4 pb-3">
                <.status_line state={row.status_state} title={row.status} />
              </div>
            </li>

            <li :for={row <- @decided_refused} class="col">
              <.list_row tag="div" kind="pedido" state={row.state} title={row.title} meta={row.meta}>
                <:leading>
                  <.service_square mark="pedidos" tone="service" />
                </:leading>
              </.list_row>
              <div class="px-4 pb-3">
                <.status_line state={row.status_state} title={row.status} />
              </div>
            </li>

            <li :for={row <- @decided_sent} class="col">
              <.list_row tag="div" kind="pedido" state={row.state} title={row.title} meta={row.meta}>
                <:leading>
                  <.service_square mark="pedidos" tone="service" />
                </:leading>
              </.list_row>
            </li>
          </ul>

          <p class="type-body-sm text-secondary">
            {gettext("Os pedidos resolvidos ficam visíveis. Você pode mudar de ideia quando quiser.")}
          </p>

          <.empty_state
            :if={@grants_error}
            icon="info"
            title={gettext("Não deu para abrir os acessos liberados")}
            body={gettext("Pode ter sido um instante de rede ou da caixa. Tente de novo.")}
          >
            <:action>
              <.button kind="secondary" phx-click="retry-grants">
                {gettext("Tentar de novo")}
              </.button>
            </:action>
          </.empty_state>
        </div>
      </div>

      <.dialog
        id="confirm-deny"
        show={@confirm_deny != nil}
        kind="destructive"
        title={gettext("Negar este pedido?")}
        body={gettext("A pessoa não vai poder abrir o arquivo. Ela pode pedir de novo depois.")}
        confirm_label={gettext("Negar")}
        on_confirm={JS.push("deny", value: %{id: @confirm_deny})}
        on_cancel={JS.push("close-confirm")}
      />

      <.dialog
        id="confirm-revoke"
        show={@confirm_revoke != nil}
        kind="destructive"
        title={revoke_title(@grants, @confirm_revoke)}
        body={gettext("Para abrir de novo, ela precisa pedir.")}
        confirm_label={gettext("Tirar acesso")}
        on_confirm={JS.push("revoke")}
        on_cancel={JS.push("close-confirm")}
      />
    </Layouts.page>
    """
  end
end
