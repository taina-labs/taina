defmodule TainaWeb.InviteAcceptLive do
  @moduledoc """
  Aceite de convite: a pessoa convidada escolhe nome e senha. O submit é um
  POST tradicional para `InviteController.accept` (`accept_invite/2` + sessão
  na mesma requisição). O token só é validado de verdade no submit, aqui ele
  apenas viaja na URL.
  """

  use TainaWeb, :live_view

  alias TainaWeb.Layouts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Aceitar convite"))
     |> assign(:token, token)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <div class="col gap-3 text-center mt-10 mb-8" style="align-items: center;">
        <.icon name="spark" size={40} class="spark" />
        <h1 class="type-h1">{gettext("Você foi convidado!")}</h1>
        <p class="type-body text-secondary">
          {gettext("Crie sua conta para entrar na nuvem da comunidade.")}
        </p>
      </div>

      <form id="invite-accept-form" action={~p"/convite/#{@token}"} method="post" class="col gap-5">
        <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
        <.input
          label={gettext("Seu nome de usuário")}
          name="account[username]"
          id="account_username"
          value=""
          placeholder={gettext("ex.: joao")}
          help={gettext("Sem espaços. É com ele que você entra na comunidade.")}
          autocapitalize="none"
          required
          minlength="3"
        />
        <.input
          label={gettext("Nome de exibição (opcional)")}
          name="account[display_name]"
          id="account_display_name"
          value=""
          placeholder={gettext("ex.: João Mendes")}
          help={gettext("Como seu nome aparece para a comunidade.")}
        />
        <.input
          label={gettext("Senha")}
          type="password"
          name="account[password]"
          id="account_password"
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
          id="account_password_confirmation"
          value=""
          placeholder={gettext("a mesma senha")}
          required
          minlength="8"
        />
        <.button type="submit" variant="primary" class="w-full mt-2">{gettext("Criar conta")}</.button>
      </form>
    </Layouts.auth>
    """
  end
end
