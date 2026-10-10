defmodule TainaWeb.AccountLive do
  @moduledoc """
  Hub "Conta" (aba do bottom-nav mobile): cartão da pessoa logada e atalhos
  para membros, convites, armazenamento, lixeira e sair. Não tem board próprio
  no Penpot, composto com os componentes de linha do design system.

  Aqui também mora a documentação dos atalhos de teclado (Cmd+1..5, briefing
  desktop): os pares espelham `TainaWeb.Hooks`, que resolve o destino no
  servidor.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    socket = assign_alerts(socket, socket.assigns.current_scope)
    {:ok, assign(socket, :page_title, gettext("Conta"))}
  end

  # O ponto total da nav (a aba Conta) vem do hook compartilhado; aqui a tela
  # separa entrada (Pedidos) de saída (Meus pedidos) para o ponto cair na linha
  # certa. Eventos do Ava (PubSub, já inscritos no shell) recomputam na hora.
  defp assign_alerts(socket, scope) do
    socket
    |> assign(:incoming_alert, Maraca.list_access_requests(scope.ava) != [])
    |> assign(:outgoing_alert, Maraca.list_my_requests(scope.ava) != [])
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, assign_alerts(socket, socket.assigns.current_scope)}
  end

  # Pares do cartão de atalhos: espelham `TainaWeb.Hooks.shortcut_path/1`
  # (1 a 5, ordem da sidebar). Se um lado mudar, o outro acompanha.
  defp shortcut_rows do
    [
      {gettext("Início"), "Cmd+1"},
      {gettext("Arquivos"), "Cmd+2"},
      {gettext("Fotos"), "Cmd+3"},
      {gettext("Moradores"), "Cmd+4"},
      {gettext("Conta"), "Cmd+5"}
    ]
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
      <h1 class="type-h1 mb-6">{gettext("Conta")}</h1>

      <div class="col gap-6 mx-auto w-full measure">
        <.card class="row gap-4">
          <.avatar name={@current_scope.ava.display_name || @current_scope.ava.username} />
          <div class="flex-1">
            <p class="type-h3">{@current_scope.ava.display_name || @current_scope.ava.username}</p>
            <p class="type-body-sm text-muted">{"@" <> @current_scope.ava.username}</p>
          </div>
          <.badge :if={Maraca.zelador?(@current_scope.ava)} variant="zelador">{gettext("Zelador(a)")}</.badge>
        </.card>

        <div class="list">
          <.list_row
            title={gettext("Pedidos")}
            meta={gettext("quem pediu para abrir seus arquivos")}
            navigate={~p"/conta/pedidos"}
          >
            <:leading><.service_square service="neutral" icon="shield" /></:leading>
            <:actions>
              <span :if={@incoming_alert} class="nav-dot" aria-hidden="true"></span>
              <.icon name="chevron-right" size={18} class="text-faint" />
            </:actions>
          </.list_row>

          <.list_row
            title={gettext("Meus pedidos")}
            meta={gettext("o que você está esperando")}
            navigate={~p"/conta/meus-pedidos"}
          >
            <:leading><.service_square service="neutral" icon="folder" /></:leading>
            <:actions>
              <span :if={@outgoing_alert} class="nav-dot" aria-hidden="true"></span>
              <.icon name="chevron-right" size={18} class="text-faint" />
            </:actions>
          </.list_row>

          <.list_row title={gettext("Moradores")} meta={gettext("quem faz parte da comunidade")} navigate={~p"/membros"}>
            <:leading><.service_square service="neutral" icon="user" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row
            :if={Maraca.zelador?(@current_scope.ava)}
            title={gettext("Convidar pessoas")}
            meta={gettext("link + QR code")}
            navigate={~p"/membros/convidar"}
          >
            <:leading><.service_square service="neutral" icon="qr" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row
            title={gettext("Armazenamento")}
            meta={gettext("uso do disco e cota")}
            navigate={~p"/armazenamento"}
          >
            <:leading><.service_square service="jaci" icon="disk" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row title={gettext("Lixeira")} meta={gettext("itens dos últimos 30 dias")} navigate={~p"/arquivos/lixeira"}>
            <:leading><.service_square service="neutral" icon="trash" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>
        </div>

        <.card class="desktop-only">
          <p class="type-label mb-1">{gettext("Atalhos do teclado")}</p>
          <p class="type-body-sm text-muted mb-4">
            {gettext("No Mac, segure Cmd e aperte o número. No Windows e no Linux, segure Ctrl.")}
          </p>
          <div class="col gap-2">
            <div class="row between" :for={{label, key} <- shortcut_rows()}>
              <span class="type-body-sm">{label}</span>
              <span class="type-mono-sm text-muted">{key}</span>
            </div>
          </div>
        </.card>

        <.link href={~p"/logout"} method="delete" class="btn btn--danger btn--md w-full">
          <.icon name="logout" size={18} /> {gettext("Sair")}
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
