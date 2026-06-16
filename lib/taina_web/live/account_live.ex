defmodule TainaWeb.AccountLive do
  @moduledoc """
  Hub "Conta" (aba do bottom-nav mobile): cartão da pessoa logada e atalhos
  para membros, convites, armazenamento, lixeira e sair. Não tem board próprio
  no Penpot, composto com os componentes de linha do design system.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Conta"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:account}
      storage_stats={assigns[:storage_stats]}
    >
      <h1 class="type-h1 mb-6">{gettext("Conta")}</h1>

      <div class="col gap-6 mx-auto w-full" style="max-width: 640px;">
        <.card class="row gap-4">
          <.avatar name={@current_scope.ava.display_name || @current_scope.ava.username} />
          <div class="flex-1">
            <p class="type-h3">{@current_scope.ava.display_name || @current_scope.ava.username}</p>
            <p class="type-body-sm text-muted">{"@" <> @current_scope.ava.username}</p>
          </div>
          <.badge :if={Maraca.zelador?(@current_scope.ava)} variant="zelador">{gettext("Zelador(a)")}</.badge>
        </.card>

        <div class="list">
          <.list_row title={gettext("Membros")} meta={gettext("quem faz parte da comunidade")} navigate={~p"/membros"}>
            <:leading><.service_square service="nhaman" icon="user" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row
            :if={Maraca.zelador?(@current_scope.ava)}
            title={gettext("Convidar pessoas")}
            meta={gettext("link + QR code")}
            navigate={~p"/membros/convidar"}
          >
            <:leading><.service_square service="ybira" icon="qr" /></:leading>
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

        <.link href={~p"/logout"} method="delete" class="btn btn--danger btn--md w-full">
          <.icon name="logout" size={18} /> {gettext("Sair")}
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
