defmodule TainaWeb.InviteLive do
  @moduledoc """
  Convite por link + QR (RFC 002 D6, RFC_003 seção 4): o zelador escolhe o papel
  e recebe a URL com token; QR renderizado no servidor (`eqrcode`, SVG inline,
  zero JS) e botões de copiar/compartilhar. O convite não pede e-mail: o token
  viaja no link e a pessoa escolhe nome e senha ao aceitar.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if Maraca.zelador?(scope.ava) do
      {:ok,
       socket
       |> assign(:page_title, gettext("Convidar pessoas"))
       |> assign(:role, "morador")
       |> assign(:invite_url, nil)}
    else
      {:ok,
       socket
       |> Phoenix.LiveView.put_flash(:error, gettext("Só quem cuida da comunidade pode convidar pessoas."))
       |> Phoenix.LiveView.redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_event("set-role", %{"role" => role}, socket) when role in ~w(morador zelador) do
    {:noreply, assign(socket, :role, role)}
  end

  def handle_event("generate", _params, socket) do
    scope = socket.assigns.current_scope
    role = String.to_existing_atom(socket.assigns.role)

    case Maraca.invite_user(scope.ava, scope.tekoa, role: role) do
      {:ok, ava} ->
        {:noreply, assign(socket, :invite_url, url(~p"/convite/#{ava.invite_token}"))}

      {:error, _reason} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível gerar o convite. Tente de novo."))}
    end
  end

  def handle_event("copied", _params, socket) do
    {:noreply, Phoenix.LiveView.put_flash(socket, :info, gettext("Link copiado!"))}
  end

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, :invite_url, nil)}
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
            <div>
              <p class="type-overline text-faint mb-2">{gettext("Papel da pessoa convidada")}</p>
              <div class="row gap-3">
                <.chip selected={@role == "morador"} phx-click="set-role" phx-value-role="morador">
                  {gettext("Morador(a)")}
                </.chip>
                <.chip selected={@role == "zelador"} phx-click="set-role" phx-value-role="zelador">
                  {gettext("Zelador(a)")}
                </.chip>
              </div>
              <p class="type-caption text-faint mt-2">
                {gettext("Morador participa da comunidade. Zelador também cuida da máquina.")}
              </p>
            </div>

            <.button type="submit" variant="primary" class="w-full">{gettext("Gerar convite")}</.button>
          </form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
