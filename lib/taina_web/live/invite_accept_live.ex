defmodule TainaWeb.InviteAcceptLive do
  @moduledoc """
  Aceite de convite (spec 6.5, boards "Convite / padrao"
  cc1037dc-e8ab-80cc-8008-d5e137c103f1 e "expirado"
  cc1037dc-e8ab-80cc-8008-d5e198c9a947): a pessoa convidada escolhe nome e
  senha. O submit é um POST tradicional para `InviteController.accept`
  (`accept_invite/2` + sessão na mesma requisição). No mount o token é
  conferido de leve (só leitura, via `Maraca.invite_status/1`): convite
  vencido ou já usado mostra o beco sem saída em vez do formulário, e a
  validação de verdade continua no POST. Campos não secretos voltam
  preenchidos pela query quando o POST falha (senha nunca viaja na URL).
  """

  use TainaWeb, :live_view

  alias Taina.Maraca
  alias TainaWeb.Layouts

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Aceitar convite"))
     |> assign(:token, token)
     |> assign(:token_status, Maraca.invite_status(token))
     |> assign(:community_name, community_name())
     |> assign(:show_contact, false)}
  end

  # Campos não secretos voltam pela URL quando o POST falha (o
  # `InviteController` redireciona com ?username=...); a pessoa não redigita
  # tudo e a senha nunca viaja na URL.
  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :prefill, Map.take(params, ["username", "display_name"]))}
  end

  # O "Voltar" do cartão, num convite vencido, só tem um lugar para onde ir:
  # entrar.
  @impl true
  def handle_event("voltar", _params, socket) do
    {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/login")}
  end

  # "Falar com quem cuida" (board `expirado`): web não abre conversa com
  # ninguém e a pessoa ainda não tem conta, então a saída é a mesma do login -
  # um cartão que diz com quem falar.
  def handle_event("contact", _params, socket) do
    {:noreply, assign(socket, :show_contact, true)}
  end

  def handle_event("close-contact", _params, socket) do
    {:noreply, assign(socket, :show_contact, false)}
  end

  # O nome da comunidade entra na frase do convite. Sem Tekoa (na prática
  # impossível: convite nasce depois do bootstrap), a frase sai sem nome em
  # vez de derrubar a tela.
  defp community_name do
    case Maraca.get_tekoa() do
      {:ok, tekoa} -> tekoa.name
      {:error, _motivo} -> nil
    end
  end

  # "Ana convidou você para a comunidade Quilombo do Café." (board): o status
  # do token não traz quem convidou, então a frase abre pela comunidade.
  defp invite_body(nil), do: gettext("Você foi convidado. Crie sua conta para entrar.")

  defp invite_body(community) do
    gettext("Você foi convidado para a comunidade %{community}. Crie sua conta para entrar.",
      community: community
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.connection_notice :if={@secure_connection? == false and @token_status == :invalid} />

      <.error_card
        :if={@token_status == :invalid}
        title={gettext("Este convite não é mais válido.")}
        retry_event="voltar"
        retry_label={gettext("Voltar")}
        retry_icon="chevron-left"
        contact_event="contact"
      />

      <.link
        :if={@token_status == :invalid}
        navigate={~p"/login"}
        class="type-label text-brand self-start"
      >
        {gettext("Voltar para entrar")}
      </.link>

      <div :if={@token_status == :ok}>
        <.link navigate={~p"/login"} class="row gap-2 items-center text-secondary self-start">
          <.icon name="chevron-left" size={20} />
          <span class="type-label">{gettext("Entrar")}</span>
        </.link>

        <div class="col gap-3 mt-6 mb-6">
          <h1 class="type-h1">{gettext("Você recebeu um convite")}</h1>
          <p class="type-body text-secondary">{invite_body(@community_name)}</p>
        </div>

        <.connection_notice :if={@secure_connection? == false} />

        <form id="invite-accept-form" action={~p"/convite/#{@token}"} method="post" class="col gap-5">
          <input type="hidden" name="_csrf_token" value={get_csrf_token()} />
          <.field
            label={gettext("Seu nome de usuário")}
            name="account[username]"
            id="account_username"
            value={@prefill["username"]}
            placeholder={gettext("ex.: joao")}
            help={gettext("Sem espaços. É com ele que você entra.")}
            autocomplete="username"
            autocapitalize="none"
            spellcheck="false"
            autocorrect="off"
            required
            minlength="3"
          />
          <.field
            label={gettext("Nome de exibição (opcional)")}
            name="account[display_name]"
            id="account_display_name"
            value={@prefill["display_name"]}
            placeholder={gettext("ex.: João Mendes")}
            help={gettext("Como seu nome aparece para a comunidade.")}
          />
          <.field
            label={gettext("Senha")}
            kind="password"
            name="account[password]"
            id="account_password"
            value=""
            placeholder={gettext("mínimo 8 caracteres")}
            help={gettext("Use uma frase longa que só você lembra.")}
            autocomplete="new-password"
            required
            minlength="8"
          >
            <:trailing><.password_toggle target="account_password" /></:trailing>
          </.field>
          <.button type="submit" kind="primary" class="w-full mt-2">{gettext("Criar conta")}</.button>
        </form>
      </div>

      <.dialog
        id="contact-help"
        show={@show_contact}
        on_cancel={JS.push("close-contact")}
      >
        <h2 id="contact-help-title" class="type-h3 mb-3">{gettext("Fale com quem cuida")}</h2>
        <p class="type-body text-secondary mb-4">
          {gettext(
            "Quem cuida da sua comunidade gera um convite novo para você. O convite vale sete dias e só pode ser usado uma vez."
          )}
        </p>
        <.button kind="secondary" class="w-full" phx-click="close-contact">
          {gettext("Entendi")}
        </.button>
      </.dialog>
    </Layouts.auth>
    """
  end
end
