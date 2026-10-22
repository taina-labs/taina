defmodule TainaWeb.AccountLive do
  @moduledoc """
  Hub "Conta" (aba do bottom-nav mobile): cartão da pessoa logada e atalhos
  para pedidos (recebidos e enviados), membros, convites, armazenamento,
  lixeira, troca da própria senha e sair. Não tem board próprio no Penpot,
  composto com os componentes de linha do design system.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_alerts(socket.assigns.current_scope)
      |> assign(:page_title, gettext("Conta"))
      |> assign(:show_password, false)
      |> assign(:password_errors, %{})

    {:ok, socket}
  end

  # O ponto da nav (a aba Conta) e o da linha "Pedidos" vem do hook
  # compartilhado; a tela so acende a linha quando ha algo esperando, recebido
  # ou enviado. Eventos do Ava (PubSub, ja inscritos no shell) recomputam.
  defp assign_alerts(socket, scope) do
    {:ok, recebidos} = Maraca.pedidos_recebidos(scope)
    {:ok, enviados} = Maraca.pedidos_enviados(scope)

    assign(socket, :pedidos_alert, recebidos != [] or enviados != [])
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, assign_alerts(socket, socket.assigns.current_scope)}
  end

  @impl true
  def handle_event("open-password", _params, socket) do
    {:noreply, assign(socket, :show_password, true)}
  end

  def handle_event("close-password", _params, socket) do
    {:noreply, close_password_modal(socket)}
  end

  # A confirmacao de senha e rito do formulario: o contexto ve so a senha
  # nova (mesma escolha do aceite de convite, `Maraca.reset_password/3` do
  # outro lado). O erro vira dica no campo que o causou, nao flash solto.
  def handle_event("change-password", %{"account" => params}, socket) do
    with :ok <- confirmation_ok?(params),
         {:ok, _ava} <-
           Maraca.update_password(
             socket.assigns.current_scope,
             params["current_password"],
             params["new_password"]
           ) do
      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(:info, gettext("Senha trocada. Da próxima vez, entre com a senha nova."))
       |> close_password_modal()}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :password_errors, password_errors(reason))}
    end
  end

  # Fechar o modal desmonta o form (`:if` do modal): na reabertura os campos
  # voltam vazios, sem senha velha preenchida.
  defp close_password_modal(socket) do
    assign(socket, show_password: false, password_errors: %{})
  end

  defp confirmation_ok?(%{"new_password" => new, "password_confirmation" => confirm}) do
    if is_binary(new) and new != "" and confirm == new, do: :ok, else: {:error, :password_mismatch}
  end

  defp confirmation_ok?(_params), do: {:error, :password_mismatch}

  # Credencial ruim aponta o campo "atual"; changeset (a regra do kernel) aponta
  # o campo "nova"; desigual aponta a confirmacao.
  defp password_errors(:invalid_credentials) do
    %{"current_password" => [gettext("Não é a sua senha atual. Confira e tente de novo.")]}
  end

  defp password_errors(%Ecto.Changeset{} = changeset) do
    %{"new_password" => Enum.map(Keyword.get_values(changeset.errors, :password), &translate_error/1)}
  end

  defp password_errors(:password_mismatch) do
    %{"password_confirmation" => [gettext("As duas senhas não são iguais.")]}
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

        <ul class="list">
          <.list_row
            title={gettext("Pedidos")}
            meta={gettext("quem pediu e o que você pediu")}
            navigate={~p"/conta/pedidos"}
          >
            <:leading><.service_square service="maraca" icon="shield" /></:leading>
            <:actions>
              <span :if={@pedidos_alert} class="nav-dot" aria-hidden="true"></span>
              <.icon name="chevron-right" size={18} class="text-faint" />
            </:actions>
          </.list_row>

          <.list_row title={gettext("Moradores")} meta={gettext("quem faz parte da comunidade")} navigate={~p"/membros"}>
            <:leading><.service_square service="maraca" icon="user" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row
            :if={Maraca.zelador?(@current_scope.ava)}
            title={gettext("Convidar pessoas")}
            meta={gettext("link + QR code")}
            navigate={~p"/membros/convidar"}
          >
            <:leading><.service_square service="maraca" icon="qr" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row
            title={gettext("Armazenamento")}
            meta={gettext("uso do disco e cota")}
            navigate={~p"/armazenamento"}
          >
            <:leading><.service_square service="ybira" icon="disk" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row title={gettext("Lixeira")} meta={gettext("itens dos últimos 30 dias")} navigate={~p"/arquivos/lixeira"}>
            <:leading><.service_square service="ybira" icon="trash" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>

          <.list_row
            title={gettext("Trocar minha senha")}
            meta={gettext("confirma a senha atual e cria outra")}
            phx-click="open-password"
          >
            <:leading><.service_square service="maraca" icon="shield" /></:leading>
            <:actions><.icon name="chevron-right" size={18} class="text-faint" /></:actions>
          </.list_row>
        </ul>

        <.button href={~p"/logout"} method="delete" variant="secondary" size="md" class="w-full">
          <.icon name="logout" size={18} /> {gettext("Sair da conta")}
        </.button>
      </div>

      <.modal id="password-modal" show={@show_password} on_cancel={JS.push("close-password")}>
        <h2 id="password-modal-title" class="type-h3 mb-3">{gettext("Trocar minha senha")}</h2>
        <p class="type-body text-secondary mb-4">
          {gettext(
            "Confirme com a senha que você usa hoje e crie uma nova. As outras pessoas não são avisadas: isso é só seu."
          )}
        </p>

        <form id="password-form" phx-submit="change-password" class="col gap-4">
          <.input
            label={gettext("Senha atual")}
            type="password"
            name="account[current_password]"
            id="account_current_password"
            value=""
            autocomplete="current-password"
            required
            errors={@password_errors["current_password"] || []}
          >
            <:trailing><.password_toggle target="account_current_password" /></:trailing>
          </.input>
          <.input
            label={gettext("Senha nova")}
            type="password"
            name="account[new_password]"
            id="account_new_password"
            value=""
            placeholder={gettext("mínimo 8 caracteres")}
            help={gettext("Pelo menos 8 caracteres. Uma frase que só você lembra é ainda melhor.")}
            autocomplete="new-password"
            required
            minlength="8"
            errors={@password_errors["new_password"] || []}
          >
            <:trailing><.password_toggle target="account_new_password" /></:trailing>
          </.input>
          <.input
            label={gettext("Confirme a senha nova")}
            type="password"
            name="account[password_confirmation]"
            id="account_password_confirmation"
            value=""
            placeholder={gettext("a mesma senha")}
            autocomplete="new-password"
            required
            minlength="8"
            errors={@password_errors["password_confirmation"] || []}
          >
            <:trailing><.password_toggle target="account_password_confirmation" /></:trailing>
          </.input>

          <div class="row gap-3 mt-2">
            <.button variant="secondary" size="md" class="flex-1" phx-click={JS.push("close-password")}>
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" variant="primary" size="md" class="flex-1" phx-disable-with={gettext("Trocando...")}>
              {gettext("Trocar senha")}
            </.button>
          </div>
        </form>
      </.modal>
    </Layouts.app>
    """
  end
end
