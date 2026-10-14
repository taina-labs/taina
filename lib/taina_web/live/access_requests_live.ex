defmodule TainaWeb.AccessRequestsLive do
  @moduledoc """
  Pedidos ("Conta -> Pedidos", RFC_003 D4), recebidos e enviados numa tela só:
  quem pediu para abrir um arquivo seu (com o motivo), o que você pediu e
  aguarda decisão, o que já foi decidido e as permissões que você liberou.

  O dono aprova (libera leitura) ou nega (a pessoa pode pedir de novo depois).
  Um pedido decidido não desaparece (RFC_003: sem resultado silencioso):
  aprovado ou recusado, ele desce para "Já decididos" com a resposta dita por
  quem pediu. O poder concedido também é legível e reversível: "Já liberados"
  lista as permissões de leitura que o dono concedeu, com quem recebeu, o
  arquivo e desde quando. Sem board próprio no Penpot, composto com os
  componentes de linha do design system.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.Layouts

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
    message = approved_message(socket.assigns.incoming_names, pedido)

    case pedido && Maraca.aprovar(socket.assigns.current_scope, pedido) do
      {:ok, _concessao} ->
        {:noreply,
         socket
         |> remove_request(id)
         |> assign_grants()
         |> Phoenix.LiveView.put_flash(:info, message)}

      result when result in [nil, {:error, :not_authorized}, {:error, :not_pending}, {:error, :not_found}] ->
        {:noreply, socket |> remove_request(id) |> decision_gone()}

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
         |> remove_request(id)
         |> Phoenix.LiveView.put_flash(:info, gettext("Pedido negado."))}

      result when result in [nil, {:error, :not_authorized}, {:error, :not_pending}, {:error, :not_found}] ->
        {:noreply,
         socket
         |> assign(:confirm_deny, nil)
         |> remove_request(id)
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
         |> assign_grants()
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

  def handle_event("retry-grants", _params, socket), do: {:noreply, assign_grants(socket)}

  defp access_gone(socket) do
    {:noreply,
     socket
     |> assign(:confirm_revoke, nil)
     |> assign_grants()
     |> Phoenix.LiveView.put_flash(:error, gettext("Este acesso já foi tirado."))}
  end

  @impl true
  def handle_info({:access_requested, _request}, socket) do
    {:noreply, assign_requests(socket)}
  end

  def handle_info({:access_request_approved, concessao}, socket) do
    message = outgoing_approved_message(socket.assigns.outgoing_names, concessao.recurso)

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

  # --- shell imperativo: assign/stream/put_flash ---

  defp assign_requests(socket) do
    scope = socket.assigns.current_scope
    {:ok, requests} = Maraca.pedidos_recebidos(scope)
    {:ok, outgoing} = Maraca.pedidos_enviados(scope)
    {:ok, decisions} = Maraca.list_my_recent_decisions(scope)

    socket
    |> assign(:requests, requests)
    |> assign(:incoming_names, incoming_names(scope, requests))
    |> assign(:any_requests?, requests != [])
    |> assign(:outgoing, outgoing)
    |> assign(:outgoing_names, outgoing_names(scope, outgoing))
    |> assign(:any_outgoing?, outgoing != [])
    |> assign(:decisions, decisions)
    |> assign(:decision_names, decision_names(scope, decisions))
    |> assign(:account_alert, account_alert?(scope))
    |> stream(:requests, requests, reset: true)
    |> assign_grants()
  end

  # A seção "Já liberados" carrega por último e decai sozinha: se falhar, o
  # resto da tela continua no ar, com o estado de erro (e a saída) só nela.
  defp assign_grants(socket) do
    scope = socket.assigns.current_scope

    case load_grants(scope) do
      {:ok, grants} ->
        socket
        |> assign(:grants, grants)
        |> assign(:grant_names, grant_names(scope, grants))
        |> assign(:any_grants?, grants != [])
        |> assign(:grants_error, false)

      {:error, _reason} ->
        socket
        |> assign(:grants, [])
        |> assign(:grant_names, %{})
        |> assign(:any_grants?, false)
        |> assign(:grants_error, true)
    end
  end

  # O Maraca devolve `{:ok, lista}` (e `{:error, motivo}` em falha de banco);
  # a borda da tela degrada para o estado de erro da seção, sem exceção.
  defp load_grants(scope), do: Maraca.concessoes_concedidas(scope)

  # Pedido resolvido entre o render e o clique (decidido em outra aba): some a
  # linha sem mensagem de erro tecnica.
  defp decision_gone(socket) do
    Phoenix.LiveView.put_flash(socket, :error, gettext("Este pedido já foi resolvido."))
  end

  defp remove_request(socket, id) do
    scope = socket.assigns.current_scope
    requests = Enum.reject(socket.assigns.requests, &(&1.id == String.to_integer(id)))

    socket
    |> stream_delete(:requests, %{id: id})
    |> assign(:requests, requests)
    |> assign(:incoming_names, incoming_names(scope, requests))
    |> assign(:any_requests?, requests != [])
    |> assign(:account_alert, account_alert?(scope))
  end

  # --- core puro: dados -> dados ---

  defp account_alert?(scope) do
    {:ok, recebidos} = Maraca.pedidos_recebidos(scope)
    {:ok, enviados} = Maraca.pedidos_enviados(scope)
    recebidos != [] or enviados != []
  end

  # A tela só mostra o vazio de verdade quando não há nada em nenhuma seção.
  defp empty?(assigns) do
    not assigns.any_requests? and not assigns.any_outgoing? and assigns.decisions == [] and
      not assigns.any_grants? and not assigns.grants_error
  end

  defp requester_name(request) do
    request.pedinte.display_name || request.pedinte.username
  end

  defp owner_name(request) do
    request.dono.display_name || request.dono.username
  end

  defp recipient_name(concessao) do
    concessao.leitor.display_name || concessao.leitor.username
  end

  # Nome do arquivo de cada pedido recebido, resolvido no escopo do dono (ele
  # pode ler o próprio arquivo). Arquivo que não existe mais vira rótulo
  # neutro, nunca erro de tela.
  defp incoming_names(scope, requests) do
    requests
    |> Enum.filter(&(&1.tipo == "ypy.file.v0"))
    |> Enum.uniq_by(& &1.recurso)
    |> Map.new(fn request -> {request.recurso, resolve_owned_name(scope, request.recurso)} end)
  end

  # Quem pediu não tem leitura (o pedido é justamente para ler), então o nome
  # vem do caminho de pedido do Ybira, que devolve o nome sem liberar o
  # arquivo. Sem resposta, rótulo neutro.
  defp outgoing_names(scope, requests) do
    requests
    |> Enum.filter(&(&1.tipo == "ypy.file.v0"))
    |> Enum.uniq_by(& &1.recurso)
    |> Map.new(fn request -> {request.recurso, resolve_requested_name(scope, request.recurso)} end)
  end

  defp resolve_owned_name(scope, rkey) do
    case Ybira.get_file(scope, rkey) do
      {:ok, file} -> file.nome
      _error -> gettext("arquivo apagado")
    end
  end

  defp resolve_requested_name(scope, rkey) do
    case Ybira.fetch_access_target(scope, rkey) do
      {:ok, %{nome: nome}} -> nome
      _error -> gettext("arquivo apagado")
    end
  end

  defp file_display_name(names, request) do
    Map.get(names, request.recurso, gettext("arquivo apagado"))
  end

  # O pedido aprovado deixa a pessoa podendo ler o arquivo (o caminho de pedido
  # responde :already_readable), então o nome sai primeiro do caminho de
  # leitura; o recusado continua pelo caminho de pedido. Sem os dois, rótulo
  # neutro.
  defp decision_names(scope, decisions) do
    decisions
    |> Enum.filter(&(&1.tipo == "ypy.file.v0"))
    |> Enum.uniq_by(& &1.recurso)
    |> Map.new(fn decision -> {decision.recurso, resolve_decision_name(scope, decision.recurso)} end)
  end

  defp resolve_decision_name(scope, rkey) do
    case Ybira.get_file(scope, rkey) do
      {:ok, file} ->
        file.nome

      _error ->
        case Ybira.fetch_access_target(scope, rkey) do
          {:ok, %{nome: nome}} -> nome
          _other -> gettext("arquivo apagado")
        end
    end
  end

  # Nome do recurso concedido, resolvido no escopo do dono (ele pode ler o que
  # concedeu). Recurso que não existe mais vira rótulo neutro: a linha segue
  # valendo, para limpar o acesso que ficou órfão.
  defp grant_names(scope, concessoes) do
    concessoes
    |> Enum.uniq_by(& &1.recurso)
    |> Map.new(fn concessao -> {concessao.recurso, resolve_resource_name(scope, concessao)} end)
  end

  defp resolve_resource_name(scope, %{tipo: "ypy.file.v0", recurso: rkey}) do
    case Ybira.get_file(scope, rkey) do
      {:ok, file} -> file.nome
      _error -> gettext("arquivo apagado")
    end
  end

  defp resolve_resource_name(scope, %{tipo: "ypy.folder.v0", recurso: rkey}) do
    case Ybira.get_folder(scope, rkey) do
      {:ok, folder} -> folder.nome
      _error -> gettext("pasta apagada")
    end
  end

  defp resolve_resource_name(_scope, _concessao), do: gettext("arquivo apagado")

  # "doc.txt, desde há 2 semanas": o que foi liberado e há quanto, calmo, sem
  # virar tabela de auditoria.
  defp grant_meta(concessao, names) do
    gettext("%{file}, desde %{when}",
      file: Map.get(names, concessao.recurso, gettext("arquivo apagado")),
      when: relative_time(concessao.concedida_em)
    )
  end

  # "Pedido para abrir relatorio.pdf, esperando Joana decidir, hoje."
  defp outgoing_meta(request, names) do
    gettext("Pedido para abrir %{file}, esperando %{name} decidir, %{when}",
      file: file_display_name(names, request),
      name: owner_name(request),
      when: relative_time(request.inserted_at)
    )
  end

  # A resposta dita por quem pediu, com o arquivo na frente para a linha não
  # ficar ambígua quando há mais de um pedido para a mesma pessoa.
  defp decision_meta(decision, names) do
    file = file_display_name(names, decision)

    case decision.status do
      :aprovado ->
        gettext("%{file}: %{name} liberou. Você já pode abrir.", file: file, name: owner_name(decision))

      :negado ->
        gettext("%{file}: %{name} recusou este pedido. Você pode pedir de novo quando quiser.",
          file: file,
          name: owner_name(decision)
        )
    end
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

  # "Ana pediu acesso a relatorio.pdf, há 3 dias." O motivo vem na sequência e
  # a linha quebra em vez de cortar com reticências (`list-row__meta--wrap`
  # no render): decidir sem ler o porquê é decidir às cegas.
  defp request_meta(request, names) do
    base =
      gettext("%{name} pediu acesso a %{file}, %{when}",
        name: requester_name(request),
        file: file_display_name(names, request),
        when: relative_time(request.inserted_at)
      )

    case request.motivo do
      nil -> base
      reason -> base <> " " <> gettext("Motivo: %{reason}", reason: reason)
    end
  end

  # Flash da aprovação nomeia o arquivo: a decisão é sobre aquele arquivo, não
  # sobre "um pedido".
  defp approved_message(names, pedido) do
    case pedido && Map.fetch(names, pedido.recurso) do
      {:ok, file} -> gettext("Acesso a %{file} liberado. A pessoa já pode ler.", file: file)
      _other -> gettext("Acesso liberado. A pessoa já pode ler.")
    end
  end

  # Aprovação chegando pelo PubSub nomeia o arquivo quando o nome já está na
  # tela (pedido que veio depois do mount deixa o flash genérico).
  defp outgoing_approved_message(names, rkey) do
    case names && Map.fetch(names, rkey) do
      {:ok, file} -> gettext("Pedido aprovado: agora você pode abrir %{file}.", file: file)
      _other -> gettext("Seu pedido foi aprovado. Você já pode abrir.")
    end
  end

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
      <Layouts.app_bar title={gettext("Pedidos")} back={~p"/conta"} />

      <div class="col gap-6 mx-auto w-full measure">
        <h1 class="desktop-only type-h1">{gettext("Pedidos")}</h1>

        <.empty_state
          :if={empty?(assigns)}
          icon="shield"
          title={gettext("Nenhum pedido por enquanto")}
          hint={gettext("Ninguém acessa seus arquivos sem você deixar. Quando alguém pedir, ou você pedir acesso a algo, aparece aqui.")}
        />

        <div :if={@any_requests?} class="col gap-2">
          <p class="type-overline text-muted">
            {ngettext(
              "%{count} pedido esperando sua resposta",
              "%{count} pedidos esperando sua resposta",
              length(@requests)
            )}
          </p>

          <ul class="list" id="requests" phx-update="stream">
            <.list_row
              :for={{dom_id, request} <- @streams.requests}
              id={dom_id}
              title={requester_name(request)}
              meta={request_meta(request, @incoming_names)}
              meta_class="list-row__meta--wrap"
            >
              <:leading><.avatar name={requester_name(request)} /></:leading>
              <:actions>
                <.button variant="ghost" size="md" phx-click="ask-deny" phx-value-id={request.id}>
                  {gettext("Negar")}
                </.button>
                <.button variant="primary" size="md" phx-click="approve" phx-value-id={request.id}>
                  {gettext("Aprovar")}
                </.button>
              </:actions>
            </.list_row>
          </ul>
        </div>

        <div :if={@any_outgoing?} class="col gap-2">
          <p class="type-overline text-muted">{gettext("Seus pedidos")}</p>

          <ul class="list">
            <.list_row
              :for={request <- @outgoing}
              title={owner_name(request)}
              meta={outgoing_meta(request, @outgoing_names)}
              meta_class="list-row__meta--wrap"
            >
              <:leading><.avatar name={owner_name(request)} /></:leading>
            </.list_row>
          </ul>
        </div>

        <div :if={@decisions != []} class="col gap-2">
          <p class="type-overline text-muted">{gettext("Já decididos")}</p>

          <ul class="list">
            <.list_row
              :for={decision <- @decisions}
              title={owner_name(decision)}
              meta={decision_meta(decision, @decision_names)}
              meta_class="list-row__meta--wrap"
            >
              <:leading><.avatar name={owner_name(decision)} /></:leading>
            </.list_row>
          </ul>
        </div>

        <div :if={@any_grants?} class="col gap-2">
          <p class="type-overline text-muted">{gettext("Já liberados")}</p>

          <ul class="list">
            <.list_row
              :for={grant <- @grants}
              title={recipient_name(grant)}
              meta={grant_meta(grant, @grant_names)}
            >
              <:leading><.avatar name={recipient_name(grant)} /></:leading>
              <:actions>
                <.button variant="ghost" size="md" phx-click="ask-revoke" phx-value-id={grant.id}>
                  {gettext("Tirar acesso")}
                </.button>
              </:actions>
            </.list_row>
          </ul>
        </div>

        <.empty_state
          :if={@grants_error}
          icon="alert"
          title={gettext("Não deu para abrir os acessos liberados")}
          hint={gettext("Pode ter sido um instante de rede ou da caixa. Tente de novo.")}
        >
          <.button variant="secondary" phx-click="retry-grants">
            {gettext("Tentar de novo")}
          </.button>
        </.empty_state>
      </div>

      <.confirm_dialog
        id="confirm-deny"
        show={@confirm_deny != nil}
        title={gettext("Negar este pedido?")}
        message={gettext("A pessoa não vai poder abrir o arquivo. Ela pode pedir de novo depois.")}
        confirm_label={gettext("Negar")}
        on_confirm={JS.push("deny", value: %{id: @confirm_deny})}
        on_cancel={JS.push("close-confirm")}
      />

      <.confirm_dialog
        id="confirm-revoke"
        show={@confirm_revoke != nil}
        title={revoke_title(@grants, @confirm_revoke)}
        message={gettext("Para abrir de novo, ela precisa pedir.")}
        confirm_label={gettext("Tirar acesso")}
        on_confirm={JS.push("revoke")}
        on_cancel={JS.push("close-confirm")}
      />
    </Layouts.app>
    """
  end
end
