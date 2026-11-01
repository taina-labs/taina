defmodule TainaWeb.InviteLive do
  @moduledoc """
  Convidar moradores (spec 6.4, boards "Convidar" do Penpot): `papel`
  cc1037dc-e8ab-80cc-8008-d5e1fee9b2ca e `link`
  cc1037dc-e8ab-80cc-8008-d5e20253520b. São dois estados de uma tela: quem
  convida escolhe o papel (RadioCards com o que cada papel pode) e recebe o
  link com QR (RFC 002 D6, RFC_003 seção 4).

  São dois QR: o link https da web (o QRCard do board) e o deep link `taina://`
  do aplicativo (contrato review 0.1.0, E). QR renderizado no servidor
  (`eqrcode`, SVG inline, zero JS); copiar e compartilhar ficam nos hooks
  Clipboard e Share. O convite não pede e-mail: o token viaja no link e a
  pessoa escolhe nome e senha ao aceitar.
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
       |> assign(:page_title, gettext("Convidar moradores"))
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

  # O rádio nativo do RadioCard manda o form inteiro no phx-change; o estado
  # do papel vive no to_form (o card reflete o valor, igual ao HTML).
  @impl true
  def handle_event("set-role", %{"invite" => %{"role" => role}}, socket) when role in ~w(morador zelador) do
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

        {:noreply,
         socket
         |> assign(invite_url: invite_url, app_url: deep_link(invite_url))
         |> Phoenix.LiveView.put_flash(:info, gettext("Convite criado. Envie o link para a pessoa."))}

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
    assigns = assign(assigns, :form, to_form(%{"role" => assigns.role}, as: :invite))

    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/moradores"} back_label={back_label("Moradores")}>
      <div class="col gap-6">
        <%= if @invite_url do %>
          <.qr_card
            svg={qr_svg(@invite_url)}
            link={@invite_url}
            id="copy-invite"
            phx-hook="Clipboard"
            data-copy={@invite_url}
          />

          <div class="col gap-2">
            <p class="type-overline text-muted">{gettext("Pelo aplicativo")}</p>
            <div class="qr-card" role="img" aria-label={gettext("QR code do convite para o aplicativo")}>
              {qr_svg(@app_url)}
            </div>
            <p class="type-body-sm text-secondary text-center">
              {gettext("No aplicativo, escaneie este QR ou cole o link no campo de convite.")}
            </p>
          </div>

          <.button
            id="share-invite"
            kind="secondary"
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
            {gettext("O convite vale por 7 dias.")}
          </p>
        <% else %>
          <form id="invite-form" phx-change="set-role" phx-submit="generate" class="col gap-5">
            <div class="col gap-3">
              <p class="type-overline text-muted">{gettext("PAPEL NO CONVITE")}</p>
              <.radio_card
                field={@form[:role]}
                value="morador"
                label={gettext("Morador")}
                description={gettext("Vê a praça e ganha uma casa própria.")}
              />
              <.radio_card
                field={@form[:role]}
                value="zelador"
                label={gettext("Zelador")}
                description={gettext("Cuida da máquina: disco, backups e convites. Para abrir uma casa, pede como todo mundo.")}
              />
            </div>

            <.button type="submit" kind="primary" class="w-full" phx-disable-with={gettext("Gerando...")}>
              {gettext("Criar convite")}
            </.button>
            <p class="type-caption text-muted">
              {gettext("Você cria convites só quando quiser. Dá para cancelar depois.")}
            </p>
          </form>
        <% end %>
      </div>
    </Layouts.page>
    """
  end
end
