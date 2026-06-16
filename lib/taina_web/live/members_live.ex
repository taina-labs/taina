defmodule TainaWeb.MembersLive do
  @moduledoc """
  Moradores da comunidade: lista com papel e estado de cada conta, busca local
  (a lista inteira já está na memória, 50 pessoas é o teto do produto) e atalho
  para convidar. Visível para qualquer morador; convidar e gerar link de
  redefinição é só quem cuida (zelador).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, members} = Maraca.list_members(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Moradores"))
     |> assign(:members, members)
     |> assign(:query, "")
     |> assign(:reset_link, nil)
     |> assign(:reset_member, nil)}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("reset-link", %{"id" => public_id}, socket) do
    scope = socket.assigns.current_scope

    with %{} = member <- Enum.find(socket.assigns.members, &(&1.public_id == public_id)),
         {:ok, ava} <- Maraca.mint_reset_link(scope, member) do
      {:noreply,
       socket
       |> assign(:reset_link, url(~p"/redefinir/#{ava.reset_token}"))
       |> assign(:reset_member, display_name(member))}
    else
      _ ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível gerar o link. Tente de novo."))}
    end
  end

  def handle_event("close-reset", _params, socket) do
    {:noreply, socket |> assign(:reset_link, nil) |> assign(:reset_member, nil)}
  end

  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  defp filtered(members, ""), do: members

  defp filtered(members, query) do
    needle = String.downcase(query)

    Enum.filter(members, fn member ->
      String.contains?(String.downcase(display_name(member)), needle)
    end)
  end

  defp display_name(member) do
    member.display_name || member.username || gettext("Convite pendente")
  end

  defp member_meta(member, scope) do
    cond do
      member.id == scope.ava.id -> gettext("Você")
      is_nil(member.activated_at) -> gettext("Convite pendente")
      member.role == :zelador -> gettext("Quem cuida da máquina")
      true -> gettext("Entrou %{when}", when: relative_time(member.inserted_at))
    end
  end

  defp can_reset?(member, scope) do
    Maraca.zelador?(scope.ava) and member.id != scope.ava.id and not is_nil(member.activated_at)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:members}
      storage_stats={assigns[:storage_stats]}
    >
      <Layouts.app_bar title={gettext("Moradores")} back={~p"/conta"}>
        <:action :if={Maraca.zelador?(@current_scope.ava)}>
          <.icon_button name="plus" label={gettext("Convidar pessoas")} navigate={~p"/membros/convidar"} />
        </:action>
      </Layouts.app_bar>

      <div class="col gap-4 mx-auto w-full" style="max-width: 640px;">
        <form id="member-search-form" phx-change="search" class="search">
          <.icon name="search" size={20} />
          <input
            type="search"
            name="query"
            value={@query}
            placeholder={gettext("Buscar pessoa")}
            phx-debounce="200"
            autocomplete="off"
          />
        </form>

        <div class="row between">
          <p class="type-overline text-faint">
            {ngettext("%{count} pessoa", "%{count} pessoas", length(@members))}
          </p>
          <.link
            :if={Maraca.zelador?(@current_scope.ava)}
            navigate={~p"/membros/convidar"}
            class="type-label text-brand"
          >
            {gettext("Convidar")}
          </.link>
        </div>

        <div class="list">
          <.list_row
            :for={member <- filtered(@members, @query)}
            title={display_name(member)}
            meta={member_meta(member, @current_scope)}
          >
            <:leading>
              <.avatar name={display_name(member)} inactive={is_nil(member.activated_at)} />
            </:leading>
            <:actions>
              <.badge :if={member.role == :zelador} variant="admin">{gettext("Zelador(a)")}</.badge>
              <.icon_button
                :if={can_reset?(member, @current_scope)}
                name="link"
                label={gettext("Gerar link de redefinição de senha")}
                phx-click="reset-link"
                phx-value-id={member.public_id}
              />
            </:actions>
          </.list_row>
        </div>

        <.empty_state
          :if={filtered(@members, @query) == []}
          icon="user"
          title={gettext("Ninguém por aqui")}
          hint={gettext("Nenhuma pessoa corresponde à busca.")}
        />
      </div>

      <.modal id="reset-link-modal" show={@reset_link != nil} on_cancel={JS.push("close-reset")}>
        <h2 class="type-h3 mb-3">{gettext("Link de redefinição de senha")}</h2>
        <p class="type-body text-secondary mb-4">
          {gettext(
            "Entregue este link para %{name} pelo mesmo canal do convite. Com ele, a pessoa cria uma senha nova. O link expira em 1 hora.",
            name: @reset_member
          )}
        </p>
        <div class="row gap-3 surface-default radius-md p-4 border-subtle mb-4">
          <span class="type-mono-sm truncate flex-1">{@reset_link}</span>
          <.icon name="link" size={18} class="text-brand" />
        </div>
        <.button id="copy-reset" variant="primary" class="w-full" phx-hook="Clipboard" data-copy={@reset_link}>
          {gettext("Copiar link")}
        </.button>
      </.modal>
    </Layouts.app>
    """
  end
end
