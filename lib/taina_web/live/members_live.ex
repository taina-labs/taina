defmodule TainaWeb.MembersLive do
  @moduledoc """
  Moradores da comunidade (spec 6.4, boards "Moradores" do Penpot): `morador`
  cc1037dc-e8ab-80cc-8008-d5e1bc7a5a02, `zelador`
  cc1037dc-e8ab-80cc-8008-d5e1c8a5c025, `busca vazia`
  cc1037dc-e8ab-80cc-8008-d5e1cd378b7e e `acoes da pessoa`
  cc1037dc-e8ab-80cc-8008-d5e1d5f3b551.

  Lista com busca local (a lista inteira já está na memória, 50 pessoas é o
  teto do produto) e, para quem cuida (zelador), a ação "Convidar" no
  cabeçalho e o menu de ações da pessoa. O papel de cada um aparece na meta da
  linha ("Zelador(a), entrou em 2024", board). Convites pendentes continuam em
  seção própria, fora da contagem de quem já entrou.

  Não há mais troca de papel nem desativação por aqui (o board as troca por
  atos de assembleia, que chegam depois do MVP): o menu da pessoa oferta o que
  a caixa faz hoje, gerar o link de redefinição de senha.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts
  alias TainaWeb.Time
  alias Ypy.Maraca.Ava

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Moradores"))
     |> assign(:query, "")
     |> assign(:reset_link, nil)
     |> assign(:reset_member, nil)
     |> assign(:confirm_revoke, nil)
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
         {:ok, %{token: token}} <- Maraca.mint_reset_link(scope, member) do
      {:noreply,
       socket
       |> assign(:reset_link, url(~p"/redefinir/#{token}"))
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

  # A guarda de clipboard fica no hook (JS); quando ele não consegue copiar
  # (origem insegura, sem permissão), a saída é a mão: selecionar o link e
  # copiar por conta própria.
  def handle_event("copy-failed", _params, socket) do
    {:noreply,
     Phoenix.LiveView.put_flash(
       socket,
       :error,
       gettext("Não deu para copiar agora. Selecione o link e copie com a mão.")
     )}
  end

  # Convite pendente se revoga apagando a linha (não tem identidade nem dados).
  def handle_event("ask-revoke", %{"id" => public_id}, socket) do
    invite = Enum.find(socket.assigns.pendings, &(&1.public_id == public_id))
    {:noreply, assign(socket, :confirm_revoke, invite)}
  end

  def handle_event("close-confirm", _params, socket) do
    {:noreply, assign(socket, :confirm_revoke, nil)}
  end

  def handle_event("revoke", %{"id" => public_id}, socket) do
    socket = assign(socket, :confirm_revoke, nil)

    case Maraca.revoke_invite(socket.assigns.current_scope, public_id) do
      {:ok, _ava} ->
        {:noreply, socket |> assign_members() |> flash_info(gettext("Convite revogado."))}

      {:error, _reason} ->
        {:noreply, flash_error(socket, gettext("Não foi possível revogar o convite. Tente de novo."))}
    end
  end

  defp assign_members(socket) do
    {:ok, all} = Maraca.list_members(socket.assigns.current_scope)
    # Convite pendente não é morador: a lista separa quem já entrou de quem
    # só foi convidado, cada um com as ações certas.
    {pendings, members} = Enum.split_with(all, &invite_pending?/1)
    members = Enum.filter(members, &active_member?/1)
    assign(socket, members: members, pendings: pendings)
  end

  defp flash_info(socket, msg), do: Phoenix.LiveView.put_flash(socket, :info, msg)
  defp flash_error(socket, msg), do: Phoenix.LiveView.put_flash(socket, :error, msg)

  # Busca sem sotaque: normaliza acentos (NFD + remove marcas) e procura no nome
  # de exibição e no nome de usuário, então "joao" acha "João" e vice-versa.
  defp filtered(members, ""), do: members

  defp filtered(members, query) do
    needle = normalize(query)

    Enum.filter(members, fn member ->
      String.contains?(normalize(display_name(member)), needle) or
        String.contains?(normalize(member.username || ""), needle)
    end)
  end

  defp normalize(value) do
    value
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{M}/u, "")
    |> String.downcase()
  end

  defp display_name(member) do
    member.display_name || member.username || gettext("Convite pendente")
  end

  # "Zeladora, entrou em 2024" (board): papel e ano de entrada. O ano é o da
  # comunidade (o banco grava em UTC; o ano de quem lê não é o do banco).
  defp member_meta(member) do
    if deactivated?(member) do
      gettext("Conta desativada")
    else
      gettext("%{role}, entrou em %{year}",
        role: role_label(member.papel),
        year: Time.local_date(member.inserted_at).year
      )
    end
  end

  defp pending_meta(invite) do
    if Maraca.invite_expired?(invite),
      do: gettext("convite expirado"),
      else: gettext("aguardando a pessoa aceitar")
  end

  # Convite ainda não aceito: a linha existe, a pessoa ainda não entrou.
  defp invite_pending?(member), do: is_nil(member.activated_at)
  defp active_member?(member), do: not is_nil(member.activated_at) and is_nil(member.deactivated_at)

  defp role_label(:zelador), do: gettext("Zelador(a)")
  defp role_label(:morador), do: gettext("Morador(a)")

  # Zelador agindo sobre outra conta (nunca a própria) e ativa: o link de
  # redefinição é para quem NAO consegue entrar, a pessoa troca a senha
  # sozinha em Conta ("Trocar senha").
  defp can_reset?(member, scope) do
    Maraca.zelador?(scope.ava) and member.id != scope.ava.id and not is_nil(member.activated_at)
  end

  defp deactivated?(member), do: not is_nil(member.deactivated_at)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/"}>
      <:action :if={Maraca.zelador?(@current_scope.ava)}>
        <.button kind="secondary" size="sm" navigate={~p"/moradores/convidar"}>
          {gettext("Convidar")}
        </.button>
      </:action>

      <div class="col gap-6">
        <% members = filtered(@members, @query) %>
        <% pendings = filtered(@pendings, @query) %>

        <%!-- phx-submit cobre a tecla "ir" do teclado mobile, que submete o
        form de verdade e recarregaria a página limpando a busca --%>
        <form id="member-search-form" phx-change="search" phx-submit="search" class="col">
          <.field
            kind="search"
            name="query"
            value={@query}
            placeholder={gettext("Buscar pessoa")}
            aria-label={gettext("Buscar pessoa")}
            autocomplete="off"
          />
        </form>

        <div :if={Maraca.zelador?(@current_scope.ava) and pendings != []} class="col gap-2">
          <p class="type-overline text-muted">{gettext("Convites pendentes")}</p>
          <ul class="list">
            <.list_row
              :for={invite <- pendings}
              kind="person"
              title={gettext("Convite pendente")}
              meta={pending_meta(invite)}
            >
              <:leading>
                <.avatar name={gettext("Convite pendente")} off />
              </:leading>
              <:actions>
                <.badge kind="inactive">{role_label(invite.papel)}</.badge>
                <.actions_menu
                  :if={Maraca.zelador?(@current_scope.ava)}
                  id={"invite-menu-#{invite.public_id}"}
                  label={gettext("Ações do convite")}
                  title={gettext("Convite pendente")}
                >
                  <:item icon="trash" kind="danger" click={JS.push("ask-revoke", value: %{id: invite.public_id})}>
                    {gettext("Revogar convite")}
                  </:item>
                </.actions_menu>
              </:actions>
            </.list_row>
          </ul>
        </div>

        <ul class="list">
          <.list_row
            :for={member <- members}
            kind="person"
            title={display_name(member)}
            meta={member_meta(member)}
            trailing={member_trailing(member, @current_scope)}
          >
            <:leading>
              <.avatar name={display_name(member)} off={deactivated?(member)} />
            </:leading>
            <:actions :if={can_reset?(member, @current_scope)}>
              <.actions_menu
                id={"member-menu-#{member.public_id}"}
                label={gettext("Ações da conta")}
                title={display_name(member)}
              >
                <:item
                  icon="link"
                  click={JS.push("reset-link", value: %{id: member.public_id})}
                >
                  {gettext("Gerar link de redefinição de senha")}
                </:item>
              </.actions_menu>
            </:actions>
          </.list_row>
        </ul>

        <.empty_state
          :if={members == [] and pendings == []}
          icon="folder"
          title={gettext("Ninguém com esse nome")}
          body={gettext("Confira a escrita ou procure por outro nome.")}
          tag="h2"
        />

        <%!-- O rodapé do board do zelador: o que o papel pode e o que ele
        nao pode (nenhum acesso à casa de ninguém). --%>
        <div :if={Maraca.zelador?(@current_scope.ava)} class="col gap-2">
          <.badge kind="zelador">{gettext("zelador")}</.badge>
          <p class="type-body-sm text-secondary">
            {gettext("Quem cuida da nuvem só convida pessoas. Ninguém pode mexer nos arquivos de outra pessoa.")}
          </p>
        </div>
      </div>

      <.dialog id="reset-link-modal" show={@reset_link != nil} on_cancel={JS.push("close-reset")}>
        <h2 id="reset-link-modal-title" class="type-h3 mb-3">{gettext("Link de redefinição de senha")}</h2>
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
        <.button id="copy-reset" kind="primary" class="w-full" phx-hook="Clipboard" data-copy={@reset_link}>
          {gettext("Copiar link")}
        </.button>
      </.dialog>

      <.dialog
        id="confirm-revoke"
        show={@confirm_revoke != nil}
        kind="destructive"
        title={gettext("Revogar este convite?")}
        body={
          gettext(
            "O link deixa de funcionar na hora: quem tiver o link não consegue mais entrar com ele. A pessoa ainda não entrou, então não some nenhuma conta. Você pode gerar um convite novo quando quiser."
          )
        }
        confirm_label={gettext("Revogar convite")}
        on_confirm={JS.push("revoke", value: %{id: @confirm_revoke && @confirm_revoke.public_id})}
        on_cancel={JS.push("close-confirm")}
      />
    </Layouts.page>
    """
  end

  # O trilho da direita: quem não tem menu (morador comum, conta própria)
  # fica com o chevron do board; quem tem ações leva o kebab delas.
  defp member_trailing(member, scope) do
    if can_reset?(member, scope), do: "action", else: "none"
  end
end
