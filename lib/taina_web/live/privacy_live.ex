defmodule TainaWeb.PrivacyLive do
  @moduledoc """
  Privacidade (spec 6.4, board "Privacidade"): pagina estatica sob `/conta`,
  no shell `page` com back para `/conta`. O copy definitivo entra em W3.5;
  por ora o corpo e um marcador.
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
    <Layouts.page flash={@flash} title={gettext("Privacidade")} back={~p"/conta"}>
      <p class="type-body-sm text-muted">
        {gettext("Conteúdo de privacidade em preparo.")}
      </p>
    </Layouts.page>
    """
  end
end
