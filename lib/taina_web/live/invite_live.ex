defmodule TainaWeb.InviteLive do
  @moduledoc """
  Convite por link + QR (RFC 002, D6): admin informa o e-mail da pessoa,
  escolhe o papel e recebe a URL com token, QR renderizado no servidor
  (`eqrcode`, SVG inline, zero JS) e botões de copiar/compartilhar.

  Nota de drift (design vs. backend): o Penpot não pede e-mail, mas
  `Maraca.invite_user/4` exige, o e-mail identifica a conta convidada.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Maraca.admin?(scope.ava) do
      {:ok,
       socket
       |> assign(:page_title, gettext("Convidar pessoas"))
       |> assign(:role, "member")
       |> assign(:email, "")
       |> assign(:invite_url, nil)
       |> assign(:error, nil)}
    else
      {:ok,
       socket
       |> Phoenix.LiveView.put_flash(:error, gettext("Só a administração pode convidar pessoas."))
       |> Phoenix.LiveView.redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("set-role", %{"role" => role}, socket) when role in ~w(member admin) do
    {:noreply, assign(socket, :role, role)}
  end

  def handle_event("generate", %{"invite" => %{"email" => email}}, socket) do
    scope = socket.assigns.current_scope
    role = String.to_existing_atom(socket.assigns.role)

    case Maraca.invite_user(scope.ava, scope.tekoa, email, role: role) do
      {:ok, ava} ->
        {:noreply,
         socket
         |> assign(:email, email)
         |> assign(:error, nil)
         |> assign(:invite_url, url(~p"/convite/#{ava.email_confirmation_token}"))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :error, invite_error(changeset))}

      {:error, :not_admin} ->
        {:noreply, assign(socket, :error, gettext("Só a administração pode convidar pessoas."))}
    end
  end

  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, socket |> assign(:invite_url, nil) |> assign(:email, "")}
  end

  defp invite_error(changeset) do
    if Keyword.has_key?(changeset.errors, :email) do
      {message, _opts} = changeset.errors[:email]

      case message do
        "has already been taken" -> gettext("Já existe uma conta com esse e-mail nesta comunidade.")
        _other -> gettext("Informe um e-mail válido.")
      end
    else
      gettext("Não foi possível gerar o convite. Tente de novo.")
    end
  end

  defp qr_svg(invite_url) do
    invite_url
    |> EQRCode.encode()
    |> EQRCode.svg(viewbox: true)
    |> Phoenix.HTML.raw()
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
      <Layouts.app_bar title={gettext("Convidar pessoas")} back={~p"/membros"} />

      <div class="col gap-6 mx-auto w-full" style="max-width: 480px;">
        <%= if @invite_url do %>
          <div class="qr-card">{qr_svg(@invite_url)}</div>
          <p class="type-body-sm text-secondary text-center">
            {gettext("Aponte a câmera ou compartilhe o link abaixo")}
          </p>

          <div>
            <p class="type-overline text-faint mb-2">{gettext("Link do convite")}</p>
            <div class="row gap-3 surface-default radius-md p-4 border-subtle">
              <span class="type-mono-sm truncate flex-1">{@invite_url}</span>
              <.icon name="link" size={18} class="text-brand" />
            </div>
          </div>

          <.button
            id="copy-invite"
            variant="primary"
            class="w-full"
            phx-hook="Clipboard"
            data-copy={@invite_url}
          >
            {gettext("Copiar link")}
          </.button>
          <.button
            id="share-invite"
            variant="secondary"
            class="w-full"
            phx-hook="Share"
            data-url={@invite_url}
            data-title={gettext("Convite para a nuvem da comunidade")}
          >
            {gettext("Compartilhar convite")}
          </.button>
          <button type="button" class="type-label text-brand text-center" phx-click="reset">
            {gettext("Convidar outra pessoa")}
          </button>
          <p class="type-caption text-faint text-center">
            {gettext("Este convite expira em 7 dias, revogável a qualquer momento.")}
          </p>
        <% else %>
          <form id="invite-form" phx-submit="generate" class="col gap-5">
            <.input
              label={gettext("E-mail da pessoa convidada")}
              type="email"
              name="invite[email]"
              id="invite_email"
              value={@email}
              placeholder="pessoa@exemplo.org"
              help={gettext("Identifica a conta. O convite em si vai por link/QR.")}
              errors={List.wrap(@error)}
              required
            />

            <div>
              <p class="type-overline text-faint mb-2">{gettext("Papel da pessoa convidada")}</p>
              <div class="row gap-3">
                <.chip selected={@role == "member"} phx-click="set-role" phx-value-role="member">
                  {gettext("Membro")}
                </.chip>
                <.chip selected={@role == "admin"} phx-click="set-role" phx-value-role="admin">
                  {gettext("Admin")}
                </.chip>
              </div>
            </div>

            <.button type="submit" variant="primary" class="w-full">{gettext("Gerar convite")}</.button>
          </form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
