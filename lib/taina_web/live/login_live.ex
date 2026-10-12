defmodule TainaWeb.LoginLive do
  @moduledoc """
  Tela de login. O form é um POST tradicional para `SessionController.create`
  (cookie nasce lá); o LiveView cuida só da apresentação. Sem e-mail (RFC_003,
  seção 4), a recuperação de senha é mediada pelo zelador: a explicação vive
  num cartão fixo embaixo do form, não num flash que some em 4 segundos.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    cond do
      not Maraca.bootstrapped?() ->
        {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/setup")}

      socket.assigns.current_scope ->
        {:ok, Phoenix.LiveView.redirect(socket, to: ~p"/")}

      true ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Entrar"))
         |> assign(:show_invite_help, false)}
    end
  end

  @impl true
  def handle_event("toggle-invite-help", _params, socket) do
    {:noreply, assign(socket, :show_invite_help, !socket.assigns.show_invite_help)}
  end

  # O campo aceita o link completo colado (ou só o código): o token é o que vem
  # depois de /convite/ no link que o QR code abre.
  def handle_event("open-invite", %{"code" => input}, socket) do
    case invite_token(input) do
      nil -> {:noreply, socket}
      code -> {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/convite/#{code}")}
    end
  end

  # Extrai o token do link (`.../convite/<token>`); sem link na colagem, o
  # texto segue cru (pode já ser só o código).
  defp invite_token(input) do
    case String.trim(input || "") do
      "" ->
        nil

      text ->
        case Regex.run(~r{/convite/([A-Za-z0-9_-]+)}, text) do
          [_link, token] -> token
          nil -> text
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="col gap-3 text-center mt-10 mb-8 items-center">
        <.icon name="spark" size={40} class="spark" />
        <h1 class="type-h1">Tainá</h1>
        <h2 class="type-h2">{gettext("Boas-vindas de volta")}</h2>
        <p class="type-body-sm text-secondary">{gettext("Entre com seu nome na nuvem da sua comunidade.")}</p>
      </div>

      <form id="login-form" action={~p"/login"} method="post" class="col gap-4">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <.input
          label={gettext("Nome de usuário")}
          type="text"
          name="username"
          id="login_username"
          value=""
          placeholder={gettext("seu nome de usuário")}
          autocomplete="username"
          autocapitalize="none"
          required
        />
        <.input
          label={gettext("Senha")}
          type="password"
          name="password"
          id="login_password"
          value=""
          placeholder={gettext("sua senha")}
          icon="shield"
          autocomplete="current-password"
          required
        />
        <.button type="submit" variant="primary" class="w-full mt-2">{gettext("Entrar")}</.button>
      </form>

      <.card class="col gap-2 mt-2">
        <div class="row gap-2 items-center">
          <.icon name="info" size={18} class="text-muted" />
          <p class="type-label">{gettext("Esqueceu a senha?")}</p>
        </div>
        <p class="type-body-sm text-secondary">
          {gettext("O Tainá não usa e-mail. Fale com quem cuida da sua comunidade: essa pessoa gera um link para você criar uma senha nova.")}
        </p>
      </.card>

      <div class="row gap-4 my-6">
        <hr class="divider flex-1" />
        <span class="type-caption text-faint">{gettext("ou")}</span>
        <hr class="divider flex-1" />
      </div>

      <.button variant="secondary" class="w-full" phx-click="toggle-invite-help">
        {gettext("Tenho um convite")}
      </.button>

      <.modal id="invite-help" show={@show_invite_help} on_cancel={JS.push("toggle-invite-help")}>
        <h2 id="invite-help-title" class="type-h3 mb-3">{gettext("Como entrar com um convite")}</h2>
        <p class="type-body text-secondary mb-4">
          {gettext(
            "Quem cuida da comunidade te manda um link (ou um QR code). É só abrir o link neste aparelho. A criação da conta acontece lá."
          )}
        </p>
        <form id="invite-code-form" phx-submit="open-invite" class="col gap-3 mb-4">
          <.input
            label={gettext("Cole aqui o link do convite")}
            name="code"
            id="invite_code"
            placeholder={gettext("o link que quem cuida te mandou")}
            help={gettext("É o mesmo link que o QR code abre.")}
            autocapitalize="none"
            spellcheck="false"
            inputmode="url"
            required
          />
          <.button type="submit" variant="primary" class="w-full" phx-disable-with={gettext("Abrindo...")}>
            {gettext("Abrir convite")}
          </.button>
        </form>
        <.button variant="secondary" class="w-full" phx-click="toggle-invite-help">
          {gettext("Entendi")}
        </.button>
      </.modal>
    </Layouts.auth>
    """
  end
end
