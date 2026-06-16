defmodule TainaWeb.ResetPasswordLive do
  @moduledoc """
  Redefinição de senha pelo link que o zelador gerou (recuperação mediada, sem
  e-mail). O submit é um POST tradicional para `PasswordController.update` (a
  sessão nasce lá); aqui o LiveView cuida só da apresentação. O token viaja na
  URL e só é validado de verdade no submit.
  """

  use TainaWeb, :live_view

  alias TainaWeb.Layouts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Redefinir senha"))
     |> assign(:token, token)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="col gap-3 text-center mt-10 mb-8 items-center">
        <.icon name="shield" size={40} class="spark" />
        <h1 class="type-h1">{gettext("Redefinir senha")}</h1>
        <p class="type-body text-secondary">
          {gettext("Crie uma senha nova para voltar a entrar.")}
        </p>
      </div>

      <form id="reset-form" action={~p"/redefinir/#{@token}"} method="post" class="col gap-5">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <.input
          label={gettext("Senha nova")}
          type="password"
          name="account[password]"
          id="reset_password"
          value=""
          placeholder={gettext("mínimo 8 caracteres")}
          icon="shield"
          help={gettext("Use uma frase longa que só você lembra.")}
          required
          minlength="8"
        />
        <.input
          label={gettext("Confirme a senha")}
          type="password"
          name="account[password_confirmation]"
          id="reset_password_confirmation"
          value=""
          placeholder={gettext("a mesma senha")}
          required
          minlength="8"
        />
        <.button type="submit" variant="primary" class="w-full mt-2">{gettext("Salvar nova senha")}</.button>
      </form>
    </Layouts.auth>
    """
  end
end
