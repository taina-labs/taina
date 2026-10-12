defmodule TainaWeb.ResetPasswordLive do
  @moduledoc """
  Redefinição de senha pelo link que o zelador gerou (recuperação mediada, sem
  e-mail). O submit é um POST tradicional para `PasswordController.update` (a
  sessão nasce lá); aqui o LiveView cuida só da apresentação. No mount o token
  é conferido de leve (`Maraca.reset_status/1`, só leitura): link vencido ou
  já usado mostra o beco sem saída em vez do formulário, e a validação de
  verdade continua no POST.
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Redefinir senha"))
     |> assign(:token, token)
     |> assign(:token_status, Maraca.reset_status(token))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.empty_state
        :if={@token_status == :invalid}
        icon="clock"
        title={gettext("Este link expirou ou já foi usado")}
        hint={gettext(
          "O link de redefinição vale uma hora e só pode ser usado uma vez. Peça um novo a quem cuida da sua comunidade."
        )}
      >
        <.button variant="primary" navigate={~p"/login"}>{gettext("Ir para o login")}</.button>
      </.empty_state>

      <div :if={@token_status == :ok}>
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
            help={gettext("Pelo menos 8 caracteres. Uma frase que só você lembra é ainda melhor.")}
            autocomplete="new-password"
            required
            minlength="8"
          >
            <:trailing><.password_toggle target="reset_password" /></:trailing>
          </.input>
          <.input
            label={gettext("Confirme a senha")}
            type="password"
            name="account[password_confirmation]"
            id="reset_password_confirmation"
            value=""
            placeholder={gettext("a mesma senha")}
            autocomplete="new-password"
            required
            minlength="8"
          >
            <:trailing><.password_toggle target="reset_password_confirmation" /></:trailing>
          </.input>
          <.button type="submit" variant="primary" class="w-full mt-2">{gettext("Salvar nova senha")}</.button>
        </form>
      </div>
    </Layouts.auth>
    """
  end
end
