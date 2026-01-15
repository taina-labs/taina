defmodule TainaWeb.HomeLive do
  @moduledoc """
  Home/Dashboard LiveView - Main entry point for Tainá superapp.
  """
  use TainaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # TODO: Get real user from session
    # For now, using mock data
    socket =
      socket
      |> assign(:page_title, "Home")
      |> assign(:user_name, "Maria")
      |> assign(:used_gb, 45)
      |> assign(:total_gb, 100)
      |> assign(:active_tab, :home)
      |> assign(:service_badges, %{ybira: 3, jaci: 0, guara: 12})
      |> assign(:activities, mock_activities())
      |> assign(:show_quota_banner, true)

    {:ok, socket}
  end

  @impl true
  def handle_event("navigate_to_" <> service, _params, socket) do
    # TODO: Navigate to service
    service_atom = String.to_existing_atom(service)
    {:noreply, assign(socket, :active_tab, service_atom)}
  end

  @impl true
  def handle_event("dismiss_quota_banner", _params, socket) do
    {:noreply, assign(socket, :show_quota_banner, false)}
  end

  @impl true
  def handle_event("open_search", _params, socket) do
    # TODO: Open search modal or navigate to search
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_settings", _params, socket) do
    # TODO: Navigate to settings
    {:noreply, socket}
  end

  @impl true
  def handle_event("open_profile", _params, socket) do
    # TODO: Navigate to profile
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="home-container">
      <%!-- Header with Search Bar --%>
      <.search_bar
        on_focus="open_search"
        on_settings_click="open_settings"
        on_profile_click="open_profile"
      />

      <%!-- Greeting and Quota Banner --%>
      <.quota_banner
        :if={@show_quota_banner}
        user_name={@user_name}
        used_gb={@used_gb}
        total_gb={@total_gb}
        on_dismiss="dismiss_quota_banner"
      />

      <%!-- Service Cards Section --%>
      <section class="px-4 mt-4 space-y-4">
        <.service_card
          service={:ybira}
          notification_count={@service_badges.ybira}
          on_click="navigate_to_ybira"
        />

        <.service_card
          service={:jaci}
          notification_count={@service_badges.jaci}
          on_click="navigate_to_jaci"
        />

        <.service_card
          service={:guara}
          notification_count={@service_badges.guara}
          on_click="navigate_to_guara"
        />
      </section>

      <%!-- Activity Feed --%>
      <section class="mt-6">
        <h2 class="px-4 text-headline text-neutral-50 mb-3">
          Atividades Recentes
        </h2>

        <div class="divide-y divide-neutral-800">
          <.activity_item
            :for={activity <- @activities}
            service={activity.service}
            title={activity.title}
            timestamp={activity.timestamp}
            preview={activity.preview}
          />
        </div>

        <div :if={@activities == []} class="px-4 py-12 text-center">
          <Lucideicons.activity class="w-16 h-16 mx-auto text-neutral-700 mb-4" />
          <h3 class="text-title text-neutral-400 mb-2">Nenhuma atividade ainda</h3>
          <p class="text-body-md text-neutral-500">
            Comece fazendo upload de arquivos, adicionando fotos ou enviando mensagens.
          </p>
        </div>
      </section>

      <%!-- Bottom Navigation --%>
      <.bottom_nav active={@active_tab} badges={@service_badges} />
    </div>
    """
  end

  # Mock data for development
  defp mock_activities do
    [
      %{
        service: :jaci,
        title: "Nova foto \"Aniversário\"",
        timestamp: ~N[2026-01-14 18:30:00],
        preview: nil
      },
      %{
        service: :guara,
        title: "Nova mensagem de @Ana",
        timestamp: ~N[2026-01-14 15:20:00],
        preview: "Viu as fotos?"
      },
      %{
        service: :ybira,
        title: "Arquivo \"Contrato.pdf\" adicionado",
        timestamp: ~N[2026-01-13 10:15:00],
        preview: nil
      },
      %{
        service: :jaci,
        title: "12 fotos adicionadas",
        timestamp: ~N[2026-01-12 08:45:00],
        preview: nil
      }
    ]
  end
end
