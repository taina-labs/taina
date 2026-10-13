defmodule TainaWeb.MyRequestsLive do
  @moduledoc """
  Pedidos que a pessoa fez ("Conta -> Meus pedidos", RFC_003 D4): o que ela
  pediu para abrir, com o arquivo nomeado, e ainda aguarda decisão do dono.
  Somente leitura, quem decide é o dono.

  Um pedido decidido não desaparece (RFC_003: sem resultado silencioso):
  aprovado ou recusado, ele desce para a seção "Já decididos" com a resposta
  dita por quem pediu, e a recusa nunca é beco sem saída, pode pedir de
  novo. Sem board próprio no Penpot, composto com os componentes de linha
  do design system.
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
     |> assign(:page_title, gettext("Meus pedidos"))
     |> assign_requests()}
  end

  @impl true
  def handle_info({:access_request_approved, concessao}, socket) do
    message = approved_message(socket.assigns.file_names, concessao.recurso)

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

  # --- shell imperativo: assign/stream ---

  defp assign_requests(socket) do
    scope = socket.assigns.current_scope
    requests = Maraca.pedidos_enviados(scope)
    decisions = Maraca.list_my_recent_decisions(scope)

    socket
    |> assign(:requests, requests)
    |> assign(:file_names, file_names(scope, requests))
    |> assign(:any_requests?, requests != [])
    |> assign(:decisions, decisions)
    |> assign(:decision_names, decision_names(scope, decisions))
    |> assign(:account_alert, account_alert?(scope))
    |> stream(:requests, requests, reset: true)
  end

  # --- core puro: dados -> dados ---

  defp account_alert?(scope) do
    Maraca.pedidos_recebidos(scope) != [] or Maraca.pedidos_enviados(scope) != []
  end

  defp owner_name(request) do
    request.dono.display_name || request.dono.username
  end

  # "Pedido para abrir relatorio.pdf, esperando Joana decidir, hoje."
  defp request_meta(request, file_names) do
    gettext("Pedido para abrir %{file}, esperando %{name} decidir, %{when}",
      file: file_display_name(file_names, request),
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

  # Quem pediu não tem leitura (o pedido é justamente para ler), então o nome
  # vem do caminho de pedido do Ybira, que devolve o nome sem liberar o
  # arquivo. Sem resposta, rótulo neutro.
  defp file_names(scope, requests) do
    requests
    |> Enum.filter(&(&1.tipo == "ypy.file.v0"))
    |> Enum.uniq_by(& &1.resource_id)
    |> Map.new(fn request -> {request.recurso, resolve_file_name(scope, request.recurso)} end)
  end

  defp resolve_file_name(scope, resource_id) do
    case Ybira.fetch_access_target(scope, resource_id) do
      {:ok, %{nome: nome}} -> nome
      _error -> gettext("arquivo apagado")
    end
  end

  # O pedido aprovado deixa a pessoa podendo ler o arquivo (o caminho de
  # pedido responde :already_readable), então o nome sai primeiro do caminho
  # de leitura; o recusado continua pelo caminho de pedido. Sem os dois,
  # rótulo neutro.
  defp decision_names(scope, decisions) do
    decisions
    |> Enum.filter(&(&1.tipo == "ypy.file.v0"))
    |> Enum.uniq_by(& &1.resource_id)
    |> Map.new(fn decision -> {decision.recurso, resolve_decision_name(scope, decision.recurso)} end)
  end

  defp resolve_decision_name(scope, resource_id) do
    case Ybira.get_file(scope, resource_id) do
      {:ok, file} ->
        file.nome

      _error ->
        case Ybira.fetch_access_target(scope, resource_id) do
          {:ok, %{nome: nome}} -> nome
          _other -> gettext("arquivo apagado")
        end
    end
  end

  defp file_display_name(file_names, request) do
    Map.get(file_names, request.recurso, gettext("arquivo apagado"))
  end

  # Aprovação chegando pelo PubSub nomeia o arquivo quando o nome já está na
  # tela (pedido que veio depois do mount deixa o flash genérico).
  defp approved_message(file_names, resource_id) do
    case file_names && Map.fetch(file_names, resource_id) do
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
      <Layouts.app_bar title={gettext("Meus pedidos")} back={~p"/conta"} />

      <div class="col gap-4 mx-auto w-full measure">
        <h1 class="desktop-only type-h1 mb-4">{gettext("Meus pedidos")}</h1>

        <div :if={@any_requests?} class="col gap-2">
          <p class="type-overline text-muted">
            {ngettext(
              "%{count} pedido esperando resposta",
              "%{count} pedidos esperando resposta",
              length(@requests)
            )}
          </p>

          <ul class="list" id="my-requests" phx-update="stream">
            <.list_row
              :for={{dom_id, request} <- @streams.requests}
              id={dom_id}
              title={owner_name(request)}
              meta={request_meta(request, @file_names)}
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
