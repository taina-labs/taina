defmodule TainaWeb.LoginLive do
  @moduledoc """
  Tela de login (spec 6.5, boards "Entrar / padrao"
  cc1037dc-e8ab-80cc-8008-d5e0e503cbf2, "erro"
  cc1037dc-e8ab-80cc-8008-d5e0e85721c9 e "Web / Entrar"
  cc1037dc-e8ab-80cc-8008-d5eb7769601d). O form é um POST tradicional para
  `SessionController.create` (cookie nasce lá); o LiveView cuida só da
  apresentação.

  Sem e-mail (RFC_003, seção 4), a recuperação de senha é mediada pelo
  zelador: o link "Esqueci minha senha" abre a explicação, a única saída é
  falar com quem cuida. "Tenho um convite" leva ao `/convite`
  (`InviteCodeLive`), onde o link ou código é colado.
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
         |> assign(:show_password_help, false)
         |> assign(:password_error, login_password_error(socket.assigns.flash))
         |> assign(:login_error, not is_nil(Phoenix.Flash.get(socket.assigns.flash, :error)))}
    end
  end

  @impl true
  def handle_event("toggle-password-help", _params, socket) do
    {:noreply, assign(socket, :show_password_help, !socket.assigns.show_password_help)}
  end

  # --- core puro: dados -> dados ---

  # O POST de login falha no SessionController e volta para cá com o flash de
  # erro; o board "erro" repete o aviso no campo da senha. Os outros erros
  # que caem no login (convite ou link de redefinição vencidos) chegam com
  # flash próprio e não acendem o campo.
  defp login_password_error(flash) do
    if Phoenix.Flash.get(flash, :error) == gettext("Não conseguimos entrar.") do
      gettext("Confira a senha e tente de novo.")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="col gap-3 text-center mt-10 mb-8 items-center">
        <h1 class="auth-title">Tainá</h1>
        <p :if={!@login_error} class="type-body text-secondary">
          {gettext("Entre com seu nome na nuvem da sua comunidade.")}
        </p>
      </div>

      <.connection_notice :if={@secure_connection? == false} />

      <form id="login-form" action={~p"/login"} method="post" class="col gap-4">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <.field
          label={gettext("Seu nome de usuário")}
          name="username"
          id="login_username"
          value=""
          placeholder={gettext("seu nome de usuário")}
          help={gettext("É com ele que você entra.")}
          autocomplete="username"
          autocapitalize="none"
          required
        />
        <.field
          label={gettext("Senha")}
          kind="password"
          name="password"
          id="login_password"
          value=""
          placeholder={gettext("sua senha")}
          autocomplete="current-password"
          errors={List.wrap(@password_error)}
          required
        >
          <:trailing><.password_toggle target="login_password" /></:trailing>
        </.field>
        <button type="button" class="auth-link" phx-click="toggle-password-help">
          {gettext("Esqueci minha senha")}
        </button>
        <.button type="submit" kind="primary" class="w-full mt-2">{gettext("Entrar")}</.button>
      </form>

      <div class="row gap-4 my-6">
        <hr class="divider flex-1" />
        <span class="type-caption text-faint">{gettext("ou")}</span>
        <hr class="divider flex-1" />
      </div>

      <.button kind="secondary" class="w-full" navigate={~p"/convite"}>
        {gettext("Tenho um convite")}
      </.button>

      <.dialog id="password-help" show={@show_password_help} on_cancel={JS.push("toggle-password-help")}>
        <h2 id="password-help-title" class="type-h3 mb-3">{gettext("Esqueceu a senha?")}</h2>
        <p class="type-body text-secondary mb-4">
          {gettext(
            "O Tainá não usa e-mail. Fale com quem cuida da sua comunidade: essa pessoa gera um link para você criar uma senha nova."
          )}
        </p>
        <.button kind="secondary" class="w-full" phx-click="toggle-password-help">
          {gettext("Entendi")}
        </.button>
      </.dialog>
    </Layouts.auth>
    """
  end
end
