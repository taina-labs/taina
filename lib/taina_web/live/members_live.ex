defmodule TainaWeb.MembersLive do
  @moduledoc """
  Membros da comunidade: lista com papel e estado de cada conta, busca local
  (a lista inteira já está na memória, 50 pessoas é o teto do produto) e
  atalho para convidar. Visível para qualquer membro; convidar é só admin.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, members} = Maraca.list_members(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Membros"))
     |> assign(:members, members)
     |> assign(:query, "")}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  defp filtered(members, ""), do: members

  defp filtered(members, query) do
    needle = String.downcase(query)

    Enum.filter(members, fn member ->
      String.contains?(String.downcase(member.username || member.email), needle)
    end)
  end

  defp display_name(member), do: member.username || member.email

  defp member_meta(member, scope) do
    cond do
      member.id == scope.ava.id -> gettext("Administração, você")
      is_nil(member.confirmed_at) -> gettext("Convite pendente")
      member.role == :admin -> gettext("Administração")
      true -> gettext("Membro, entrou %{when}", when: relative_time(member.inserted_at))
    end
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
      <Layouts.app_bar title={gettext("Membros")} back={~p"/conta"}>
        <:action :if={Maraca.admin?(@current_scope.ava)}>
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
            :if={Maraca.admin?(@current_scope.ava)}
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
              <.avatar name={display_name(member)} inactive={is_nil(member.confirmed_at)} />
            </:leading>
            <:actions>
              <.badge :if={member.role == :admin} variant="admin">{gettext("Admin")}</.badge>
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
    </Layouts.app>
    """
  end
end
