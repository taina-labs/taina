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
    numeric_id = String.to_integer(id)
    message = approved_message(socket.assigns.requests, socket.assigns.file_names, numeric_id)

    case Maraca.approve_access_request(socket.assigns.current_scope.ava, numeric_id) do
      {:ok, _permission} ->
        {:noreply,
         socket
         |> remove_request(id)
         |> assign_grants()
         |> Phoenix.LiveView.put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, handle_decision_error(socket, reason, id, &approve_error/1)}
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
    case Maraca.deny_access_request(socket.assigns.current_scope.ava, String.to_integer(id)) do
      {:ok, _request} ->
        {:noreply,
         socket
         |> assign(:confirm_deny, nil)
         |> remove_request(id)
         |> Phoenix.LiveView.put_flash(:info, gettext("Pedido negado."))}

      {:error, reason} ->
        {:noreply, socket |> assign(:confirm_deny, nil) |> handle_decision_error(reason, id, &deny_error/1)}
    end
  end

  # Acesso que sumiu entre abrir a confirmação e confirmar (outra aba tirou
  # primeiro, ou o pedido já não existe mais): recarrega em vez de culpar
  # ninguém, a lista volta certa.
  def handle_event("revoke", _params, socket) do
    grant = find_grant(socket.assigns.grants, socket.assigns.confirm_revoke)

    case grant && revoke_grant(socket.assigns.current_scope.ava, grant) do
      :ok ->
        {:noreply,
         socket
         |> assign(:confirm_revoke, nil)
         |> assign_grants()
         |> Phoenix.LiveView.put_flash(:info, revoked_message(grant))}

      result when result in [nil, {:error, :not_found}] ->
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

  defp revoke_grant(revoker, grant) do
    Maraca.revoke_permission(revoker, grant.ava, :read, grant.resource_type, grant.resource_id)
  end

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
    requests = Maraca.list_access_requests(scope.ava)

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

  # O Maraca devolve a lista crua e levanta em falha de banco; na borda da
  # tela resolvemos para o tuple de resultado, sem exceção como controle.
  defp load_grants(scope) do
    {:ok, Maraca.list_my_grants(scope.ava)}
  rescue
    _error -> {:error, :load_failed}
  end

  # Pedido resolvido entre o render e o clique (decidido em outra aba): some a
  # linha sem mensagem de erro tecnica.
  defp handle_decision_error(socket, reason, id, _mapper) when reason in [:invalid_status, :not_found] do
    socket
    |> remove_request(id)
    |> Phoenix.LiveView.put_flash(:error, gettext("Este pedido já foi resolvido."))
  end

  defp handle_decision_error(socket, reason, _id, mapper) do
    Phoenix.LiveView.put_flash(socket, :error, mapper.(reason))
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
    Maraca.list_access_requests(scope.ava) != [] or Maraca.list_my_requests(scope.ava) != []
  end

  # Nome do arquivo de cada pedido, resolvido no escopo do dono (o pedido traz
  # o public_id; o dono pode ler o próprio arquivo). Arquivo que não existe
  # mais vira rótulo neutro, nunca erro de tela.
  defp file_names(scope, requests) do
    requests
    |> Enum.filter(&(&1.resource_type == "ybira_file"))
    |> Enum.uniq_by(& &1.resource_id)
    |> Map.new(fn request -> {request.resource_id, resolve_file_name(scope, request.resource_id)} end)
  end

  defp resolve_file_name(scope, resource_id) do
    case Ybira.get_file(scope, resource_id) do
      {:ok, file} -> file.original_filename
      _error -> gettext("arquivo apagado")
    end
  end

  defp file_display_name(file_names, request) do
    Map.get(file_names, request.resource_id, gettext("arquivo apagado"))
  end

  defp requester_name(request) do
    request.requester.display_name || request.requester.username
  end

  defp recipient_name(grant) do
    grant.ava.display_name || grant.ava.username
  end

  # Nome do recurso concedido, resolvido no escopo do dono (ele pode ler o que
  # concedeu). Recurso que não existe mais vira rótulo neutro: a linha segue
  # valendo, para limpar o acesso que ficou órfão.
  defp grant_names(scope, grants) do
    grants
    |> Enum.uniq_by(& &1.resource_id)
    |> Map.new(fn grant -> {grant.resource_id, resolve_resource_name(scope, grant)} end)
  end

  defp resolve_resource_name(scope, %{resource_type: "ybira_file", resource_id: resource_id}) do
    case Ybira.get_file(scope, resource_id) do
      {:ok, file} -> file.original_filename
      _error -> gettext("arquivo apagado")
    end
  end

  defp resolve_resource_name(scope, %{resource_type: "ybira_folder", resource_id: resource_id}) do
    case Ybira.get_folder(scope, resource_id) do
      {:ok, folder} -> folder.name
      _error -> gettext("pasta apagada")
    end
  end

  defp resolve_resource_name(_scope, _grant), do: gettext("arquivo apagado")

  # "doc.txt, desde há 2 semanas": o que foi liberado e há quanto, calmo, sem
  # virar tabela de auditoria.
  defp grant_meta(grant, names) do
    gettext("%{file}, desde %{when}",
      file: Map.get(names, grant.resource_id, gettext("arquivo apagado")),
      when: relative_time(grant.inserted_at)
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

    case request.reason do
      nil -> base
      reason -> base <> " " <> gettext("Motivo: %{reason}", reason: reason)
    end
  end

  # Flash da aprovação nomeia o arquivo: a decisão é sobre aquele arquivo, não
  # sobre "um pedido".
  defp approved_message(requests, file_names, id) do
    request = Enum.find(requests, &(&1.id == id))

    case request && Map.fetch(file_names, request.resource_id) do
      {:ok, file} -> gettext("Acesso a %{file} liberado. A pessoa já pode ler.", file: file)
      _other -> gettext("Acesso liberado. A pessoa já pode ler.")
    end
  end

  defp approve_error(:not_owner), do: gettext("Este pedido não é seu para decidir.")
  defp approve_error(_reason), do: gettext("Este pedido já foi resolvido.")

  defp deny_error(:not_owner), do: gettext("Este pedido não é seu para decidir.")
  defp deny_error(_reason), do: gettext("Este pedido já foi resolvido.")

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

          <div class="list" id="requests" phx-update="stream">
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
          </div>
        </div>

        <.empty_state
          :if={!@any_requests?}
          icon="shield"
          title={gettext("Nenhum pedido por enquanto")}
          hint={gettext("Ninguém acessa seus arquivos sem você deixar. Quando alguém pedir, aparece aqui.")}
        />

        <div :if={@any_grants?} class="col gap-2">
          <p class="type-overline text-muted">{gettext("Já liberados")}</p>

          <div class="list">
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
          </div>
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
