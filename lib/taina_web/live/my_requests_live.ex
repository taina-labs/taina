defmodule TainaWeb.MyRequestsLive do
  @moduledoc """
  Pedidos que a pessoa fez ("Conta -> Meus pedidos", RFC_003 D4): o que ela
  pediu para abrir e ainda aguarda decisao do dono. Somente leitura, quem decide
  e o dono. Sem board proprio no Penpot, composto com os componentes de linha do
  design system.
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
     |> assign(:page_title, gettext("Meus pedidos"))
     |> assign_requests()}
  end

  @impl true
  def handle_info({:access_request_approved, _permission}, socket) do
    {:noreply,
     socket
     |> assign_requests()
     |> Phoenix.LiveView.put_flash(:info, gettext("Seu pedido foi aprovado. Você já pode abrir."))}
  end

  def handle_info({:access_request_denied, _request}, socket) do
    {:noreply,
     socket
     |> assign_requests()
     |> Phoenix.LiveView.put_flash(:info, gettext("Seu pedido foi negado."))}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  # --- shell imperativo: assign/stream ---

  defp assign_requests(socket) do
    requests = Maraca.list_my_requests(socket.assigns.current_scope.ava)

    socket
    |> assign(:any_requests?, requests != [])
    |> assign(:account_alert, account_alert?(socket.assigns.current_scope))
    |> stream(:requests, requests, reset: true)
  end

  # --- core puro: dados -> dados ---

  defp account_alert?(scope) do
    Maraca.list_access_requests(scope.ava) != [] or Maraca.list_my_requests(scope.ava) != []
  end

  defp owner_name(request) do
    request.owner.display_name || request.owner.username
  end

  defp request_subtitle(request) do
    gettext("Esperando %{name} decidir, %{when}",
      name: owner_name(request),
      when: relative_time(request.inserted_at)
    )
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
      <Layouts.app_bar title={gettext("Meus pedidos")} back={~p"/conta"} />

      <div class="col gap-4 mx-auto w-full measure">
        <div class="list" id="my-requests" phx-update="stream">
          <.list_row :for={{dom_id, request} <- @streams.requests} id={dom_id} title={owner_name(request)} meta={request_subtitle(request)}>
            <:leading><.avatar name={owner_name(request)} /></:leading>
          </.list_row>
        </div>

        <.empty_state
          :if={!@any_requests?}
          icon="shield"
          title={gettext("Você não tem pedidos abertos")}
          hint={gettext("Quando você pedir acesso a um arquivo, ele aparece aqui até a pessoa decidir.")}
        />
      </div>
    </Layouts.app>
    """
  end
end
