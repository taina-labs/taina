defmodule TainaWeb.AccountLive do
  @moduledoc """
  Conta (spec 6.4, boards "Conta" do Penpot): `morador`
  cc1037dc-e8ab-80cc-8008-d5e23c048bf9, `zelador`
  cc1037dc-e8ab-80cc-8008-d5e261192f2d e W cc1037dc-e8ab-80cc-8008-d5eaef8a5541.

  O cartão da pessoa (avatar, nome, papel e comunidade) e as linhas do dia a
  dia: Pedidos (com o que está esperando), Convidar (só quem
  cuida), Trocar senha (sobe no sheet com o formulário) e Dispositivos (os
  aparelhos com acesso, cada um revogável). "Sair" encerra a sessão. O que o
  board tirou daqui (Lixeira, Moradores, Armazenamento, Convites) mora nas
  próprias telas ou no hub.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.InternalPath
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_pedidos(socket.assigns.current_scope)
      |> assign(:devices, [])
      |> assign(:devices_error, false)
      |> assign(:page_title, gettext("Conta"))
      |> assign(:password_errors, %{})
      |> assign(:show_devices, false)
      |> assign(:show_password, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    {:noreply, assign(socket, :return_to, InternalPath.from_uri(uri))}
  end

  # A revogação é do ciclo de vida: aparelho revogado sai da lista.
  defp active_devices(devices), do: Enum.filter(devices, &is_nil(&1.revoked_at))

  # A meta distingue o que o morador precisa responder dos pedidos que enviou.
  # Eventos do Ava (PubSub) recalculam os dois totais.
  defp assign_pedidos(socket, scope) do
    with {:ok, recebidos} <- Maraca.pedidos_recebidos(scope),
         {:ok, enviados} <- Maraca.pedidos_enviados(scope) do
      socket
      |> assign(:pedidos_meta, pedidos_meta(length(recebidos), length(enviados)))
      |> assign(:pedidos_error, false)
    else
      {:error, _reason} ->
        socket
        |> assign(:pedidos_meta, gettext("Não foi possível carregar os pedidos agora."))
        |> assign(:pedidos_error, true)
    end
  end

  @impl true
  def handle_info(_message, socket) do
    {:noreply, assign_pedidos(socket, socket.assigns.current_scope)}
  end

  @impl true
  def handle_event("open_password", _params, socket) do
    {:noreply, assign(socket, :show_password, true)}
  end

  def handle_event("close_password", _params, socket) do
    {:noreply, close_password_sheet(socket)}
  end

  def handle_event("retry_pedidos", _params, socket) do
    {:noreply, assign_pedidos(socket, socket.assigns.current_scope)}
  end

  def handle_event("open_devices", _params, socket) do
    case Maraca.list_devices(socket.assigns.current_scope) do
      {:ok, devices} ->
        {:noreply,
         socket
         |> assign(:devices, active_devices(devices))
         |> assign(:devices_error, false)
         |> assign(:show_devices, true)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:devices, [])
         |> assign(:devices_error, true)
         |> assign(:show_devices, true)}
    end
  end

  def handle_event("close_devices", _params, socket) do
    {:noreply, close_devices_sheet(socket)}
  end

  # Revogar um aparelho tira o acesso dele na hora (o app precisa entrar de
  # novo). Idempotente no contexto; a lista volta do banco.
  def handle_event("revoke_device", %{"id" => public_id}, socket) do
    scope = socket.assigns.current_scope

    case Maraca.revoke_device(scope, public_id) do
      {:ok, _device} ->
        case Maraca.list_devices(scope) do
          {:ok, devices} ->
            {:noreply,
             socket
             |> assign(:devices, active_devices(devices))
             |> assign(:devices_error, false)
             |> Phoenix.LiveView.put_flash(:info, gettext("Acesso do aparelho revogado."))}

          {:error, _reason} ->
            {:noreply,
             socket
             |> assign(:devices, [])
             |> assign(:devices_error, true)
             |> Phoenix.LiveView.put_flash(
               :info,
               gettext("Acesso revogado. Não foi possível atualizar a lista agora.")
             )}
        end

      {:error, _reason} ->
        {:noreply,
         Phoenix.LiveView.put_flash(
           socket,
           :error,
           gettext("Não foi possível revogar o aparelho agora. Tente de novo.")
         )}
    end
  end

  # A confirmacao de senha e rito do formulario: o contexto ve so a senha
  # nova (mesma escolha do aceite de convite, `Maraca.reset_password/3` do
  # outro lado). O erro vira dica no campo que o causou, nao flash solto. A
  # web nao tem aparelho de chamada: a troca derruba os aparelhos todos.
  def handle_event("change_password", %{"account" => params}, socket) do
    with :ok <- confirmation_ok?(params),
         {:ok, _ava} <-
           Maraca.update_password(
             socket.assigns.current_scope,
             params["current_password"],
             params["new_password"]
           ),
         :ok <- Maraca.revoke_other_devices(socket.assigns.current_scope, except: nil) do
      {:noreply,
       socket
       |> Phoenix.LiveView.put_flash(:info, gettext("Senha trocada. Da próxima vez, entre com a senha nova."))
       |> close_password_sheet()}
    else
      {:error, reason} ->
        {:noreply, assign(socket, :password_errors, password_errors(reason))}
    end
  end

  # Fechar o sheet desmonta o form (`:if` do sheet): na reabertura os campos
  # voltam vazios, sem senha velha preenchida.
  defp close_devices_sheet(socket) do
    socket |> assign(:show_devices, false) |> assign(:devices, [])
  end

  defp close_password_sheet(socket) do
    socket |> assign(:show_password, false) |> assign(:password_errors, %{})
  end

  defp confirmation_ok?(%{"new_password" => new, "password_confirmation" => confirm}) do
    if is_binary(new) and new != "" and confirm == new, do: :ok, else: {:error, :password_mismatch}
  end

  defp confirmation_ok?(_params), do: {:error, :password_mismatch}

  # Credencial ruim aponta o campo "atual"; rate limit estourado tambem e da
  # hora de tentar (a dica diz para esperar); changeset (a regra do kernel)
  # aponta o campo "nova"; desigual aponta a confirmacao.
  defp device_meta(device) do
    case device.last_used_at do
      nil -> gettext("Nunca usado")
      at -> gettext("usado %{when}", when: relative_time(at))
    end
  end

  defp invite_path(return_to), do: ~p"/moradores/convidar?#{[return_to: return_to]}"

  defp password_errors(:invalid_credentials) do
    %{"current_password" => [gettext("Não é a sua senha atual. Confira e tente de novo.")]}
  end

  defp password_errors(:rate_limited) do
    %{"current_password" => [gettext("Muitas tentativas seguidas. Espere um pouco e tente de novo.")]}
  end

  defp password_errors(%Ecto.Changeset{} = changeset) do
    %{"new_password" => Enum.map(Keyword.get_values(changeset.errors, :password), &translate_error/1)}
  end

  defp password_errors(:password_mismatch) do
    %{"password_confirmation" => [gettext("As duas senhas não são iguais.")]}
  end

  # --- core puro: dados -> dados ---

  # Pedidos enviados esperam resposta de outra pessoa, não do morador.
  defp pedidos_meta(0, 0), do: gettext("Nada pendente")

  defp pedidos_meta(received, _sent) when received > 0 do
    gettext("%{count} esperando sua resposta", count: received)
  end

  defp pedidos_meta(0, sent), do: ngettext("1 pedido enviado", "%{count} pedidos enviados", sent)

  # "Moradora, Quilombo do Café" (board): papel e comunidade no cartão.
  defp person_meta(scope) do
    gettext("%{role}, %{community}",
      role: role_label(scope.ava.papel),
      community: scope.tekoa.name
    )
  end

  defp role_label(:zelador), do: gettext("Zelador(a)")
  defp role_label(:morador), do: gettext("Morador(a)")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/"}>
      <div class="col gap-6">
        <.card class="row items-center gap-4">
          <.avatar name={person_name(@current_scope.ava)} />
          <div class="flex-1">
            <p class="type-h3">{person_name(@current_scope.ava)}</p>
            <p class="type-body-sm text-muted">{person_meta(@current_scope)}</p>
          </div>
        </.card>

        <ul class="list">
          <.list_row kind="civic" trailing="chevron" title={gettext("Pedidos")} meta={@pedidos_meta} navigate={~p"/conta/pedidos"}>
            <:leading><.service_square mark="pedidos" /></:leading>
          </.list_row>

          <.list_row
            :if={Maraca.zelador?(@current_scope.ava)}
            kind="civic"
            trailing="chevron"
            title={gettext("Convidar")}
            meta={gettext("Criar um convite")}
            navigate={invite_path(@return_to)}
          >
            <:leading><.service_square mark="moradores" /></:leading>
          </.list_row>

          <.list_row
            kind="civic"
            trailing="chevron"
            title={gettext("Trocar senha")}
            meta={gettext("Atualize a sua senha")}
            phx-click="open_password"
          >
            <:leading><.service_square mark="senha" /></:leading>
          </.list_row>

          <.list_row
            kind="civic"
            trailing="chevron"
            title={gettext("Dispositivos")}
            meta={gettext("Aparelhos com acesso")}
            phx-click="open_devices"
          >
            <:leading><.service_square mark="dispositivos" /></:leading>
          </.list_row>
        </ul>

        <.error_card
          :if={@pedidos_error}
          title={gettext("Não conseguimos carregar os pedidos agora.")}
          retry_event="retry_pedidos"
        />

        <.button href={~p"/logout"} method="delete" kind="secondary" size="lg" icon="sair" class="w-full">
          {gettext("Sair")}
        </.button>
      </div>

      <.sheet id="password-sheet" show={@show_password} on_cancel="close_password" kind="content" title={gettext("Trocar senha")}>
        <form id="password-form" phx-submit="change_password" phx-auto-recover="ignore" class="col gap-4">
          <p class="type-body text-secondary">
            {gettext("Confirme com a senha que você usa hoje e crie uma nova. As outras pessoas não são avisadas: isso é só seu.")}
          </p>
          <.field
            kind="password"
            label={gettext("Senha atual")}
            name="account[current_password]"
            id="account_current_password"
            value=""
            autocomplete="current-password"
            required
            errors={@password_errors["current_password"] || []}
          >
            <:trailing><.password_toggle target="account_current_password" /></:trailing>
          </.field>
          <.field
            kind="password"
            label={gettext("Senha nova")}
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
          </.field>
          <.field
            kind="password"
            label={gettext("Confirme a senha nova")}
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
          </.field>

          <div class="row gap-3 mt-2">
            <.button kind="secondary" size="md" class="flex-1" phx-click={JS.push("close_password")}>
              {gettext("Cancelar")}
            </.button>
            <.button type="submit" kind="primary" size="md" class="flex-1" phx-disable-with={gettext("Trocando...")}>
              {gettext("Trocar senha")}
            </.button>
          </div>
        </form>
      </.sheet>

      <.sheet id="devices-sheet" show={@show_devices} on_cancel="close_devices" kind="content" title={gettext("Dispositivos")}>
        <div class="col gap-2">
          <p class="type-body-sm text-secondary">
            {gettext("Aparelhos com acesso à sua conta. Revogar não apaga nada da caixa: o aparelho só precisa entrar de novo.")}
          </p>

          <.error_card
            :if={@devices_error}
            title={gettext("Não conseguimos carregar os dispositivos agora.")}
            retry_event="open_devices"
          />

           <ul class="list">
           <.list_row
             kind="person"
             title={gettext("Este navegador")}
             meta={gettext("Sessão atual")}
           >
             <:leading><.service_square mark="dispositivos" /></:leading>
             <:actions><.badge kind="active">{gettext("Atual")}</.badge></:actions>
           </.list_row>

           <.list_row
             :for={device <- @devices}
              kind="person"
              title={device.name}
              meta={device_meta(device)}
            >
              <:actions>
                <.button kind="ghost" size="sm" phx-click="revoke_device" phx-value-id={device.public_id}>
                  {gettext("Revogar")}
                </.button>
              </:actions>
            </.list_row>
          </ul>

           <p :if={@devices == []} class="type-body-sm text-muted">
             {gettext("Nenhum outro aparelho com acesso agora.")}
           </p>
        </div>
      </.sheet>
    </Layouts.page>
    """
  end
end
