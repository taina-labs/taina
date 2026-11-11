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
     |> assign(:show_contact, false)
     |> assign(:token, token)
     |> assign(:token_status, Maraca.reset_status(token))}
  end

  # O "Voltar" do cartão, num link vencido, só tem um lugar para onde ir:
  # entrar.
  @impl true
  def handle_event("voltar", _params, socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/login")}
  end

  # "Falar com quem cuida" (board `expirado`): sem conta e sem conversa no
  # web, a saída é o cartão que diz com quem falar.
  def handle_event("contact", _params, socket) do
    {:noreply, assign(socket, :show_contact, true)}
  end

  def handle_event("close_contact", _params, socket) do
    {:noreply, assign(socket, :show_contact, false)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.connection_notice :if={@secure_connection? == false and @token_status == :invalid} />

      <.error_card
        :if={@token_status == :invalid}
        title={gettext("Este link expirou.")}
        retry_event="voltar"
        retry_label={gettext("Voltar")}
        retry_icon="chevron-left"
        contact_event="contact"
      />

      <div :if={@token_status == :ok}>
        <div class="col gap-3 mt-10 mb-8">
          <h1 class="type-h1">{gettext("Redefinir senha")}</h1>
          <p class="type-body text-secondary">
            {gettext("Crie uma senha nova para voltar a entrar.")}
          </p>
        </div>

        <.connection_notice :if={@secure_connection? == false} />

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

      <.dialog
        id="contact-help"
        show={@show_contact}
        on_cancel={JS.push("close_contact")}
      >
        <h2 id="contact-help-title" class="type-h3 mb-3">{gettext("Fale com quem cuida")}</h2>
        <p class="type-body text-secondary mb-4">
          {gettext(
            "Quem cuida da sua comunidade gera um link novo para você, que vale uma hora e só pode ser usado uma vez."
          )}
        </p>
        <.button kind="secondary" class="w-full" phx-click="close_contact">
          {gettext("Entendi")}
        </.button>
      </.dialog>
    </Layouts.auth>
    """
  end
end
