defmodule TainaWeb.AccessRequestsLive do
  @moduledoc """
  Caixa de pedidos do dono ("Conta -> Pedidos", RFC_003 D4): quem pediu para
  abrir um arquivo seu. O dono aprova (libera leitura) ou nega (a pessoa pode
  pedir de novo depois). Sem board proprio no Penpot, composto com os
  componentes de linha do design system.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket), do: Maraca.subscribe_to_my_events(scope.ava)

    {:ok,
     socket
     |> assign(:page_title, gettext("Pedidos"))
     |> assign(:confirm_deny, nil)
     |> assign_requests()}
  end

  @impl true
  def handle_event("approve", %{"id" => id}, socket) do
    case Maraca.approve_access_request(socket.assigns.current_scope.ava, String.to_integer(id)) do
      {:ok, _permission} ->
        {:noreply,
         socket
         |> remove_request(id)
         |> Phoenix.LiveView.put_flash(:info, gettext("Acesso liberado. A pessoa já pode ler."))}

      {:error, reason} ->
        {:noreply, handle_decision_error(socket, reason, id, &approve_error/1)}
    end
  end

  def handle_event("ask-deny", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_deny, id)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_deny, nil)}
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

  @impl true
  def handle_info({:access_requested, _request}, socket) do
    {:noreply, assign_requests(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- shell imperativo: assign/stream/put_flash ---

  defp assign_requests(socket) do
    requests = Maraca.list_access_requests(socket.assigns.current_scope.ava)

    socket
    |> assign(:any_requests?, requests != [])
    |> assign(:account_alert, account_alert?(socket.assigns.current_scope))
    |> stream(:requests, requests, reset: true)
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
    socket
    |> stream_delete(:requests, %{id: id})
    |> assign(:any_requests?, Maraca.list_access_requests(socket.assigns.current_scope.ava) != [])
    |> assign(:account_alert, account_alert?(socket.assigns.current_scope))
  end

  # --- core puro: dados -> dados ---

  defp account_alert?(scope) do
    Maraca.list_access_requests(scope.ava) != [] or Maraca.list_my_requests(scope.ava) != []
  end

  defp requester_name(request) do
    request.requester.display_name || request.requester.username
  end

  defp request_subtitle(request) do
    gettext("%{name} pediu acesso, %{when}",
      name: requester_name(request),
      when: relative_time(request.inserted_at)
    )
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
        <div class="list" id="requests" phx-update="stream">
          <.list_row :for={{dom_id, request} <- @streams.requests} id={dom_id} title={requester_name(request)} meta={request_subtitle(request)}>
            <:leading><.avatar name={requester_name(request)} /></:leading>
            <:actions>
              <.button variant="ghost" size="sm" phx-click="ask-deny" phx-value-id={request.id}>
                {gettext("Negar")}
              </.button>
              <.button variant="primary" size="sm" phx-click="approve" phx-value-id={request.id}>
                {gettext("Aprovar")}
              </.button>
            </:actions>
          </.list_row>
        </div>

        <.empty_state
          :if={!@any_requests?}
          icon="shield"
          title={gettext("Nenhum pedido por enquanto")}
          hint={gettext("Ninguém acessa seus arquivos sem você deixar. Quando alguém pedir, aparece aqui.")}
        />
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
    </Layouts.app>
    """
  end
end
