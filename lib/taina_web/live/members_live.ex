defmodule TainaWeb.MembersLive do
  @moduledoc """
  Moradores da comunidade: lista com papel e estado de cada conta, busca local
  (a lista inteira já está na memória, 50 pessoas é o teto do produto) e atalho
  para convidar. Visível para qualquer morador; convidar e gerar link de
  redefinição é só quem cuida (zelador).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias Taina.Maraca.Ava
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Moradores"))
     |> assign(:query, "")
     |> assign(:reset_link, nil)
     |> assign(:reset_member, nil)
     |> assign(:confirm_deactivate, nil)
     |> assign_members()}
  end

  @impl true
  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, assign(socket, :query, query)}
  end

  def handle_event("reset-link", %{"id" => public_id}, socket) do
    scope = socket.assigns.current_scope
    member = Enum.find(socket.assigns.members, &(&1.public_id == public_id))

    with %Ava{} <- member,
         {:ok, ava} <- Maraca.mint_reset_link(scope, member) do
      {:noreply,
       socket
       |> assign(:reset_link, url(~p"/redefinir/#{ava.reset_token}"))
       |> assign(:reset_member, display_name(member))}
    else
      _ -> {:noreply, flash_error(socket, gettext("Não foi possível gerar o link. Tente de novo."))}
    end
  end

  def handle_event("close-reset", _params, socket) do
    {:noreply, socket |> assign(:reset_link, nil) |> assign(:reset_member, nil)}
  end

  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  def handle_event("set-role", %{"id" => public_id, "role" => role}, socket) do
    role = String.to_existing_atom(role)

    case Maraca.update_member_role(socket.assigns.current_scope, public_id, role) do
      {:ok, _ava} ->
        {:noreply, socket |> assign_members() |> flash_info(gettext("Papel atualizado."))}

      {:error, :last_zelador} ->
        {:noreply, flash_error(socket, last_zelador_message())}

      {:error, _reason} ->
        {:noreply, flash_error(socket, gettext("Não foi possível mudar o papel. Tente de novo."))}
    end
  end

  def handle_event("ask-deactivate", %{"id" => public_id}, socket) do
    member = Enum.find(socket.assigns.members, &(&1.public_id == public_id))
    {:noreply, assign(socket, :confirm_deactivate, member)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_deactivate, nil)}
  end

  def handle_event("deactivate", %{"id" => public_id}, socket) do
    socket = assign(socket, :confirm_deactivate, nil)

    case Maraca.deactivate_member(socket.assigns.current_scope, public_id) do
      {:ok, _ava} ->
        {:noreply, socket |> assign_members() |> flash_info(gettext("Conta desativada."))}

      {:error, :last_zelador} ->
        {:noreply, flash_error(socket, last_zelador_message())}

      {:error, _reason} ->
        {:noreply, flash_error(socket, gettext("Não foi possível desativar a conta. Tente de novo."))}
    end
  end

  def handle_event("reactivate", %{"id" => public_id}, socket) do
    case Maraca.reactivate_member(socket.assigns.current_scope, public_id) do
      {:ok, _ava} ->
        {:noreply, socket |> assign_members() |> flash_info(gettext("Conta reativada."))}

      {:error, _reason} ->
        {:noreply, flash_error(socket, gettext("Não foi possível reativar a conta. Tente de novo."))}
    end
  end

  defp assign_members(socket) do
    {:ok, members} = Maraca.list_members(socket.assigns.current_scope)
    assign(socket, :members, members)
  end

  defp flash_info(socket, msg), do: Phoenix.LiveView.put_flash(socket, :info, msg)
  defp flash_error(socket, msg), do: Phoenix.LiveView.put_flash(socket, :error, msg)

  defp last_zelador_message do
    gettext("A comunidade precisa de pelo menos um zelador ativo. Promova outra pessoa antes.")
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
      deactivated?(member) -> gettext("Conta desativada")
      member.id == scope.ava.id -> gettext("Você")
      is_nil(member.activated_at) -> gettext("Convite pendente")
      member.role == :zelador -> gettext("Quem cuida da máquina")
      true -> gettext("Entrou %{when}", when: relative_time(member.inserted_at))
    end
  end

  defp can_reset?(member, scope) do
    Maraca.zelador?(scope.ava) and member.id != scope.ava.id and not is_nil(member.activated_at)
  end

  # Zelador agindo sobre outra conta (nunca a própria): pode mudar papel e
  # (des)ativar. A proteção do último zelador é reforçada no context.
  defp manageable?(member, scope) do
    Maraca.zelador?(scope.ava) and member.id != scope.ava.id
  end

  defp deactivated?(member), do: not is_nil(member.deactivated_at)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      active_tab={:members}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <Layouts.app_bar title={gettext("Moradores")} back={~p"/conta"}>
        <:action :if={Maraca.zelador?(@current_scope.ava)}>
          <.icon_button name="plus" label={gettext("Convidar pessoas")} navigate={~p"/membros/convidar"} />
        </:action>
      </Layouts.app_bar>

      <div class="col gap-4 mx-auto w-full measure">
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
              <.avatar
                name={display_name(member)}
                inactive={is_nil(member.activated_at) or deactivated?(member)}
              />
            </:leading>
            <:actions>
              <.badge :if={member.role == :zelador} variant="zelador">{gettext("Zelador(a)")}</.badge>
              <.icon_button
                :if={can_reset?(member, @current_scope)}
                name="link"
                label={gettext("Gerar link de redefinição de senha")}
                phx-click="reset-link"
                phx-value-id={member.public_id}
              />
              <.menu
                :if={manageable?(member, @current_scope)}
                id={"member-menu-#{member.public_id}"}
                label={gettext("Ações da conta")}
              >
                <:item
                  :if={member.role == :morador}
                  icon="shield"
                  click={JS.push("set-role", value: %{id: member.public_id, role: "zelador"})}
                >
                  {gettext("Tornar zelador(a)")}
                </:item>
                <:item
                  :if={member.role == :zelador}
                  icon="user"
                  click={JS.push("set-role", value: %{id: member.public_id, role: "morador"})}
                >
                  {gettext("Tornar morador(a)")}
                </:item>
                <:item
                  :if={not deactivated?(member)}
                  icon="logout"
                  danger
                  click={JS.push("ask-deactivate", value: %{id: member.public_id})}
                >
                  {gettext("Desativar conta")}
                </:item>
                <:item
                  :if={deactivated?(member)}
                  icon="restore"
                  click={JS.push("reactivate", value: %{id: member.public_id})}
                >
                  {gettext("Reativar conta")}
                </:item>
              </.menu>
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

      <.confirm_dialog
        id="confirm-deactivate"
        show={@confirm_deactivate != nil}
        title={gettext("Desativar esta conta?")}
        message={
          gettext(
            "%{name} não vai mais conseguir entrar. Os dados ficam guardados e você pode reativar quando quiser.",
            name: @confirm_deactivate && display_name(@confirm_deactivate)
          )
        }
        confirm_label={gettext("Desativar")}
        on_confirm={
          JS.push("deactivate", value: %{id: @confirm_deactivate && @confirm_deactivate.public_id})
        }
        on_cancel={JS.push("close-confirm")}
      />
    </Layouts.app>
    """
  end
end
