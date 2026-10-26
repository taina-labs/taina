defmodule TainaWeb.ResetPasswordLive do
  @moduledoc """
  Redefinição de senha pelo link que o zelador gerou (recuperação mediada, sem
  e-mail; spec 6.5, boards "Redefinir / padrao"
  cc1037dc-e8ab-80cc-8008-d5e19abb9e90 e "expirado"
  cc1037dc-e8ab-80cc-8008-d5e19e56bc3d). O submit é um POST tradicional para
  `PasswordController.update` (a sessão nasce lá); aqui o LiveView cuida só da
  apresentação. No mount o token é conferido de leve (`Maraca.reset_status/1`,
  só leitura): link vencido ou já usado mostra o beco sem saída em vez do
  formulário, e a validação de verdade continua no POST.
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

  # O "Tentar de novo" do cartão, num link vencido, só tem um lugar para onde
  # ir: entrar.
  @impl true
  def handle_event("voltar", _params, socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/login")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash} secure_connection?={@secure_connection?}>
      <.error_card
        :if={@token_status == :invalid}
        title={gettext("Este link expirou.")}
        body={gettext(
          "O link de redefinição vale uma hora e só pode ser usado uma vez. Peça um novo a quem cuida da sua comunidade."
        )}
        retry_event="voltar"
      />

      <div :if={@token_status == :ok}>
        <div class="col gap-3 text-center mt-10 mb-8 items-center">
          <h1 class="type-h1">{gettext("Redefinir senha")}</h1>
          <p class="type-body text-secondary">
            {gettext("Crie uma senha nova para voltar a entrar.")}
          </p>
        </div>

        <form id="reset-form" action={~p"/redefinir/#{@token}"} method="post" class="col gap-5">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <.field
            label={gettext("Senha nova")}
            kind="password"
            name="account[password]"
            id="reset_password"
            value=""
            placeholder={gettext("mínimo 8 caracteres")}
            help={gettext("Use uma frase longa que só você lembra.")}
            autocomplete="new-password"
            required
            minlength="8"
          >
            <:trailing><.password_toggle target="reset_password" /></:trailing>
          </.field>
          <.button type="submit" kind="primary" class="w-full mt-2">{gettext("Salvar nova senha")}</.button>
        </form>
      </div>
    </Layouts.auth>
    """
  end
end
