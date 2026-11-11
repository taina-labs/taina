defmodule TainaWeb.InviteCodeLive do
  @moduledoc """
  "Tenho um convite" (`/convite`, spec 6.5, board "Convite colar"
  88db615f-12f9-80b9-8008-d6329edbdcc6): um campo para colar o link ou o
  código que quem cuida mandou. O parser puro (`TainaWeb.InviteCode`) decide
  o caminho; link de outra comunidade é rejeitado com aviso próprio (a web
  não troca de instância). QR code e campo de endereço são do aplicativo, não
  da web (spec 6.5).
  """

  use TainaWeb, :live_view

  import Phoenix.LiveView, only: [connected?: 1, get_connect_info: 2]

  alias TainaWeb.InviteCode
  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    # O host da requisição decide se o link colado é desta comunidade; o
    # parser precisa dele no evento do submit, então monta aqui (depois do
    # connect não dá para pedir de novo). Sem URI, aceita qualquer host.
    uri = if connected?(socket), do: get_connect_info(socket, :uri), else: Map.get(socket, :host_uri)

    {:ok,
     socket
     |> assign(:code, nil)
     |> assign(:code_error, nil)
     |> assign(:community_host, uri && uri.host)
     |> assign(:page_title, gettext("Convite"))}
  end

  # O parser decide: link desta comunidade (ou só o código) navega para o
  # aceite; link de outra comunidade e lixo voltam com o erro no campo.
  @impl true
  def handle_event("continue", %{"code" => input}, socket) do
    case InviteCode.parse(input, socket.assigns.community_host) do
      {:ok, token} ->
        {:noreply, Phoenix.LiveView.push_navigate(socket, to: ~p"/convite/#{token}")}

      {:error, :other_community} ->
        {:noreply,
         socket
         |> assign(:code, String.trim(input))
         |> assign(:code_error, gettext("Esse convite é de outra comunidade."))}

      {:error, :invalid} ->
        {:noreply,
         socket
         |> assign(:code, String.trim(input))
         |> assign(:code_error, gettext("Esse link não é um convite."))}
    end
  end

  def handle_event("continue", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <.link navigate={~p"/login"} class="row gap-2 items-center text-secondary self-start">
        <.icon name="chevron-left" size={20} />
        <span class="type-label">{gettext("Entrar")}</span>
      </.link>

      <div class="col gap-2 mt-6 mb-6">
        <h1 class="type-h1">{gettext("Colar um convite")}</h1>
        <p class="type-body text-secondary">{gettext("Cole o link ou o código que você recebeu.")}</p>
      </div>

      <.connection_notice :if={@secure_connection? == false} />

      <form id="invite-code-form" phx-submit="continue" phx-auto-recover="ignore" class="col gap-4">
        <.field
          label={gettext("Link ou código do convite")}
          name="code"
          id="invite_code"
          value={@code}
          placeholder={gettext("ex.: taina.local/convite/abc123")}
          help={gettext("Cole o link inteiro ou só o código.")}
          errors={List.wrap(@code_error)}
          autocapitalize="none"
          spellcheck="false"
          required
        />
        <.button type="submit" kind="primary" class="w-full" phx-disable-with={gettext("Abrindo...")}>
          {gettext("Continuar")}
        </.button>
      </form>
    </Layouts.auth>
    """
  end
end
