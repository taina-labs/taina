defmodule TainaWeb.InviteLive do
  @moduledoc """
  Convite por link + QR (RFC 002 D6, RFC_003 seção 4): o zelador escolhe o papel
  e recebe a URL com token; QR renderizado no servidor (`eqrcode`, SVG inline,
  zero JS) e botões de copiar/compartilhar. São dois QR: o link https da web e
  o deep link `taina://` do aplicativo (contrato review 0.1.0, E). O convite não
  pede e-mail: o token viaja no link e a pessoa escolhe nome e senha ao aceitar.
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
       |> assign(:invite_url, nil)
       |> assign(:app_url, nil)}
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

  def handle_event("set-role", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("generate", _params, socket) do
    scope = socket.assigns.current_scope
    role = String.to_existing_atom(socket.assigns.role)

    case Maraca.invite_user(scope.ava, scope.tekoa, role: role) do
      {:ok, %{token: token}} ->
        invite_url = url(~p"/convite/#{token}")

        {:noreply, assign(socket, invite_url: invite_url, app_url: deep_link(invite_url))}

      {:error, _reason} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, gettext("Não foi possível gerar o convite. Tente de novo."))}
    end
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

  def handle_event("reset", _params, socket) do
    {:noreply, assign(socket, invite_url: nil, app_url: nil)}
  end

  # O deep link do app (contrato review 0.1.0, E): o mesmo token, com o host
  # da caixa, no scheme proprio -- o que o app sabe abrir direto (e o que o
  # QR dedicado codifica). O host e a autoridade do proprio link de convite
  # (host com porta, quando ha).
  defp deep_link(invite_url) do
    uri = URI.parse(invite_url)
    token = uri.path |> String.split("/") |> List.last()

    "taina://convite/#{token}?host=#{uri.authority}"
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
      mobile_active_tab={:account}
      storage_stats={assigns[:storage_stats]}
      account_alert={assigns[:account_alert] || false}
    >
      <Layouts.app_bar title={gettext("Convidar pessoas")} back={~p"/membros"} />

      <div class="col gap-6 mx-auto w-full measure-sm">
        <%= if @invite_url do %>
          <div>
            <p class="type-overline text-faint mb-2">{gettext("Pelo navegador")}</p>
            <div class="qr-card" role="img" aria-label={gettext("QR code do link de convite")}>
              {qr_svg(@invite_url)}
            </div>
            <p class="type-body-sm text-secondary text-center">
              {gettext("Aponte a câmera ou compartilhe o link abaixo")}
            </p>
          </div>

          <div>
            <p class="type-overline text-faint mb-2">{gettext("Pelo aplicativo")}</p>
            <div class="qr-card" role="img" aria-label={gettext("QR code do convite para o aplicativo")}>
              {qr_svg(@app_url)}
            </div>
            <p class="type-body-sm text-secondary text-center">
              {gettext("No aplicativo, escaneie este QR ou cole o link no campo de convite.")}
            </p>
          </div>

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
            data-title={gettext("Convite para a caixa da comunidade")}
          >
            {gettext("Compartilhar convite")}
          </.button>
          <button type="button" class="type-label text-brand text-center" phx-click="reset">
            {gettext("Convidar outra pessoa")}
          </button>
          <p class="type-caption text-muted text-center">
            {gettext("Qualquer pessoa com este link entra na comunidade. Compartilhe só com quem você quer convidar.")}
          </p>
          <p class="type-caption text-faint text-center">
            {gettext("Este convite expira em 7 dias.")}
          </p>
          <p class="type-caption text-faint text-center">
            {gettext("Convites gerados antes continuam valendo, cada um pelos seus 7 dias.")}
          </p>
        <% else %>
          <form id="invite-form" phx-submit="generate" class="col gap-5">
            <div>
              <p class="type-overline text-faint mb-2">{gettext("Papel da pessoa convidada")}</p>
              <div class="col gap-3" role="radiogroup" aria-label={gettext("Papel da pessoa convidada")}>
                <button
                  type="button"
                  role="radio"
                  aria-checked={to_string(@role == "morador")}
                  class={["radio-card", @role == "morador" && "radio-card--selected"]}
                  phx-click="set-role"
                  phx-value-role="morador"
                >
                  <div class="flex-1">
                    <p class="type-label">{gettext("Morador(a)")}</p>
                    <p class="type-body-sm text-muted">{gettext("participa da comunidade")}</p>
                  </div>
                  <span class="radio-card__ring"></span>
                </button>
                <button
                  type="button"
                  role="radio"
                  aria-checked={to_string(@role == "zelador")}
                  class={["radio-card", @role == "zelador" && "radio-card--selected"]}
                  phx-click="set-role"
                  phx-value-role="zelador"
                >
                  <div class="flex-1">
                    <p class="type-label">{gettext("Zelador(a)")}</p>
                    <p class="type-body-sm text-muted">
                      {gettext("também cuida da máquina. Para abrir a casa de alguém, pede acesso.")}
                    </p>
                  </div>
                  <span class="radio-card__ring"></span>
                </button>
              </div>
            </div>

            <.button type="submit" variant="primary" class="w-full" phx-disable-with={gettext("Gerando...")}>
              {gettext("Gerar convite")}
            </.button>
          </form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
