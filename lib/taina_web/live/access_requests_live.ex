defmodule TainaWeb.AccessRequestsLive do
  @moduledoc """
  Caixa de pedidos do dono ("Conta -> Pedidos", RFC_003 D4): quem pediu para
  abrir um arquivo seu, com o arquivo nomeado e o motivo explicado. O dono
  aprova (libera leitura) ou nega (a pessoa pode pedir de novo depois).

  O poder concedido também é legível e reversível (RFC_003): a seção "Já
  liberados" lista as permissões de leitura que o dono concedeu, com quem
  recebeu, o arquivo e desde quando. Tirar o acesso pede confirmação, e
  quem perdeu o acesso volta a precisar pedir. Sem board próprio no Penpot,
  composto com os componentes de linha do design system.
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
    message = approved_message(socket.assigns.requests, socket.assigns.file_names, pedido)

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

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- shell imperativo: assign/stream/put_flash ---

  defp assign_requests(socket) do
    scope = socket.assigns.current_scope
    {:ok, requests} = Maraca.pedidos_recebidos(scope)

    socket
    |> assign(:requests, requests)
    |> assign(:file_names, file_names(scope, requests))
    |> assign(:any_requests?, requests != [])
    |> assign(:account_alert, account_alert?(scope))
    |> stream(:requests, requests, reset: true)
    |> assign_grants()
  end

  # A seção "Já liberados" carrega por último e decai sozinha: se falhar, a
  # caixa de pedidos continua no ar, com o estado de erro (e a saída) só nela.
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
    |> assign(:file_names, file_names(scope, requests))
    |> assign(:any_requests?, requests != [])
    |> assign(:account_alert, account_alert?(scope))
  end

  # --- core puro: dados -> dados ---

  defp account_alert?(scope) do
    {:ok, recebidos} = Maraca.pedidos_recebidos(scope)
    {:ok, enviados} = Maraca.pedidos_enviados(scope)
    recebidos != [] or enviados != []
  end

  # Nome do arquivo de cada pedido, resolvido no escopo do dono (o pedido traz
  # o rkey; o dono pode ler o próprio arquivo). Arquivo que não existe mais
  # vira rótulo neutro, nunca erro de tela.
  defp file_names(scope, requests) do
    requests
    |> Enum.filter(&(&1.tipo == "ypy.file.v0"))
    |> Enum.uniq_by(& &1.recurso)
    |> Map.new(fn request -> {request.recurso, resolve_file_name(scope, request.recurso)} end)
  end

  defp resolve_file_name(scope, rkey) do
    case Ybira.get_file(scope, rkey) do
      {:ok, file} -> file.nome
      _error -> gettext("arquivo apagado")
    end
  end

  defp file_display_name(file_names, request) do
    Map.get(file_names, request.recurso, gettext("arquivo apagado"))
  end

  defp requester_name(request) do
    request.pedinte.display_name || request.pedinte.username
  end

  defp recipient_name(concessao) do
    concessao.leitor.display_name || concessao.leitor.username
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
  defp request_meta(request, file_names) do
    base =
      gettext("%{name} pediu acesso a %{file}, %{when}",
        name: requester_name(request),
        file: file_display_name(file_names, request),
        when: relative_time(request.inserted_at)
      )

    case request.motivo do
      nil -> base
      reason -> base <> " " <> gettext("Motivo: %{reason}", reason: reason)
    end
  end

  # Flash da aprovação nomeia o arquivo: a decisão é sobre aquele arquivo, não
  # sobre "um pedido".
  defp approved_message(_requests, file_names, pedido) do
    case pedido && Map.fetch(file_names, pedido.recurso) do
      {:ok, file} -> gettext("Acesso a %{file} liberado. A pessoa já pode ler.", file: file)
      _other -> gettext("Acesso liberado. A pessoa já pode ler.")
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

      <div class="col gap-4 mx-auto w-full measure">
        <h1 class="desktop-only type-h1 mb-4">{gettext("Pedidos")}</h1>

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
              meta={request_meta(request, @file_names)}
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

        <.empty_state
          :if={!@any_requests?}
          icon="shield"
          title={gettext("Nenhum pedido por enquanto")}
          hint={gettext("Ninguém acessa seus arquivos sem você deixar. Quando alguém pedir, aparece aqui.")}
        />

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

        <p :if={!@any_grants? and !@grants_error} class="type-body-sm text-secondary">
          {gettext("Ninguém tem acesso liberado aos seus arquivos.")}
        </p>

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
