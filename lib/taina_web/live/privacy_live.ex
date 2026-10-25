defmodule TainaWeb.PrivacyLive do
  @moduledoc """
  Privacidade (spec 6.4, board "Privacidade" cc1037dc-e8ab-80cc-8008-d5e239511ea7):
  página estática sob `/conta`, no shell `page`, com o mesmo copy do board:
  o que a casa protege, o que publicar na praça quer dizer, e a saída honesta
  de que aqui estão palavras, não promessa técnica.
  """

  use TainaWeb, :live_view

  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Privacidade"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.page flash={@flash} title={@page_title} back={~p"/conta"} back_label={back_label("Conta")}>
      <div class="col gap-6">
        <.card class="col gap-2">
          <h2 class="type-h3">{gettext("Sua casa é só sua")}</h2>
          <p class="type-body text-secondary">
            {gettext("Ninguém abre um arquivo da sua casa sem você deixar: quem pede, você aprova ou recusa.")}
          </p>
        </.card>

        <.card class="col gap-2">
          <h2 class="type-h3">{gettext("A praça é de todos")}</h2>
          <p class="type-body text-secondary">
            {gettext("O que você publica na praça, todo mundo lê. Publicar é um gesto seu, e dá para voltar atrás.")}
          </p>
          <p class="type-caption text-muted">{gettext("Casa por padrão. Praça por escolha.")}</p>
        </.card>

        <p class="type-body-sm text-secondary">
          {gettext("Sem promessa técnica aqui: só o que acontece com os seus arquivos, em palavras simples.")}
        </p>
      </div>
    </Layouts.page>
    """
  end
end
