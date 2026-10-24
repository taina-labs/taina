defmodule TainaWeb.InviteCodeLive do
  @moduledoc """
  "Tenho um convite" (spec 6.5, board "Convite colar"): tela pública sob
  `/convite`, no shell `auth`, com um campo para colar o link ou o código do
  convite. O parser (`TainaWeb.InviteCode.parse/1`) e o copy definitivo entram
  em W3.6; por ora o formulário é marcador e não navega.
  """

  use TainaWeb, :live_view

  alias TainaWeb.Layouts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, gettext("Convite"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.auth flash={@flash}>
      <h1 class="type-h3 mb-4">{gettext("Tenho um convite")}</h1>
      <form phx-submit="continue" class="col gap-4">
        <.input label={gettext("Link ou código do convite")} name="code" />
        <.button type="submit" variant="primary" size="md" class="w-full">
          {gettext("Continuar")}
        </.button>
      </form>
    </Layouts.auth>
    """
  end
end
