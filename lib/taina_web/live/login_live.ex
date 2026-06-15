defmodule TainaWeb.LoginLive do
  @moduledoc """
  Tela de login. O form é um POST tradicional para `SessionController.create`
  (cookie nasce lá); o LiveView cuida só da apresentação e dos atalhos
  ("esqueci minha senha", "tenho um convite").
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
  def handle_event("forgot-password", _params, socket) do
    # Sem SMTP no MVP (RFC 002, D6): a redefinição passa pela administração.
    {:noreply,
     Phoenix.LiveView.put_flash(
       socket,
       :info,
       gettext("Fale com quem administra sua comunidade para redefinir a senha.")
     )}
  end

  def handle_event("toggle-invite-help", _params, socket) do
    {:noreply, assign(socket, :show_invite_help, !socket.assigns.show_invite_help)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="col gap-3 text-center mt-10 mb-8" style="align-items: center;">
        <.icon name="spark" size={40} class="spark" />
        <h1 class="type-h1">Tainá</h1>
        <h2 class="type-h2">{gettext("Bem-vindo de volta")}</h2>
        <p class="type-body-sm text-secondary">{gettext("Entre na nuvem da sua comunidade.")}</p>
      </div>

      <form id="login-form" action={~p"/login"} method="post" class="col gap-4">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <.input
          label={gettext("E-mail")}
          type="email"
          name="email"
          id="login_email"
          value=""
          placeholder="voce@exemplo.org"
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
          required
        />
        <button type="button" class="type-label text-brand text-right" phx-click="forgot-password">
          {gettext("Esqueci minha senha")}
        </button>
        <.button type="submit" variant="primary" class="w-full mt-2">{gettext("Entrar")}</.button>
      </form>

      <div class="row gap-4 my-6" style="align-items: center;">
        <hr class="divider flex-1" />
        <span class="type-caption text-faint">{gettext("ou")}</span>
        <hr class="divider flex-1" />
      </div>

      <.button variant="secondary" class="w-full" phx-click="toggle-invite-help">
        {gettext("Tenho um convite")}
      </.button>

      <.modal id="invite-help" show={@show_invite_help} on_cancel={JS.push("toggle-invite-help")}>
        <h2 class="type-h3 mb-3">{gettext("Como entrar com um convite")}</h2>
        <p class="type-body text-secondary mb-4">
          {gettext(
            "Quem administra a comunidade te manda um link (ou um QR code). É só abrir o link neste aparelho. A criação da conta acontece lá."
          )}
        </p>
        <.button variant="secondary" class="w-full" phx-click="toggle-invite-help">
          {gettext("Entendi")}
        </.button>
      </.modal>
    </Layouts.auth>
    """
  end
end
