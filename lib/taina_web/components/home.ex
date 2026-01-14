defmodule TainaWeb.Components.Home do
  @moduledoc """
  Home/Dashboard specific components for Tainá.
  All components are pre-styled with the Tainá design system.
  """
  use Phoenix.Component

  import TainaWeb.Components.UI

  @doc """
  Renders a service card for the home dashboard.

  ## Examples

      <.service_card
        service={:ybira}
        notification_count={3}
        on_click="navigate_to_ybira"
      />
  """
  attr :service, :atom, required: true, values: [:ybira, :jaci, :guara]
  attr :notification_count, :integer, default: 0
  attr :on_click, :string, default: nil

  def service_card(assigns) do
    assigns =
      assigns
      |> assign(:service_name, service_name(assigns.service))
      |> assign(:service_description, service_description(assigns.service))
      |> assign(:service_color, service_color(assigns.service))

    ~H"""
    <div
      class="service-card"
      phx-click={@on_click}
    >
      <div class={["service-card-icon rounded-xl flex items-center justify-center", @service_color]}>
        <%= case @service do %>
          <% :ybira -> %>
            <Lucideicons.folder class="w-6 h-6 text-white" />
          <% :jaci -> %>
            <Lucideicons.image class="w-6 h-6 text-white" />
          <% :guara -> %>
            <Lucideicons.message_circle class="w-6 h-6 text-white" />
        <% end %>
      </div>

      <div class="service-card-content">
        <h3 class="text-title text-neutral-50"><%= @service_name %></h3>
        <p class="text-body-md text-neutral-400"><%= @service_description %></p>
      </div>

      <.badge :if={@notification_count > 0} count={@notification_count} color={@service_color} />
    </div>
    """
  end

  @doc """
  Renders an activity feed item.

  ## Examples

      <.activity_item
        service={:ybira}
        title="Arquivo compartilhado"
        timestamp={~N[2026-01-14 10:30:00]}
        preview="Contrato.pdf"
        on_click="view_activity"
      />
  """
  attr :service, :atom, required: true
  attr :title, :string, required: true
  attr :timestamp, :any, required: true
  attr :preview, :string, default: nil
  attr :on_click, :string, default: nil

  def activity_item(assigns) do
    assigns =
      assigns
      |> assign(:service_name, service_name(assigns.service))
      |> assign(:service_color, service_color(assigns.service))
      |> assign(:formatted_time, format_timestamp(assigns.timestamp))

    ~H"""
    <div class="activity-item" phx-click={@on_click}>
      <div class={["activity-icon", @service_color, "bg-opacity-10"]}>
        <%= case @service do %>
          <% :ybira -> %>
            <Lucideicons.folder class="w-5 h-5 text-ybira" />
          <% :jaci -> %>
            <Lucideicons.image class="w-5 h-5 text-jaci" />
          <% :guara -> %>
            <Lucideicons.message_circle class="w-5 h-5 text-guara" />
        <% end %>
      </div>

      <div class="activity-content">
        <h4 class="text-base font-medium text-neutral-50"><%= @title %></h4>
        <p class="text-body-sm text-neutral-400">
          <%= @service_name %> · <%= @formatted_time %>
        </p>
        <p :if={@preview} class="text-body-md text-neutral-500 truncate mt-1">
          <%= @preview %>
        </p>
      </div>
    </div>
    """
  end

  @doc """
  Renders the global search bar for the home screen.
  """
  attr :placeholder, :string, default: "Buscar em tudo..."
  attr :on_focus, :string, default: nil
  attr :on_settings_click, :string, default: nil
  attr :on_profile_click, :string, default: nil

  def search_bar(assigns) do
    ~H"""
    <div class="px-4 pt-4 pb-2">
      <div class="search-bar" phx-click={@on_focus}>
        <Lucideicons.search class="w-5 h-5 text-neutral-400" />
        <span class="text-body-md text-neutral-400 flex-1"><%= @placeholder %></span>
        <button phx-click={@on_settings_click} class="p-1">
          <Lucideicons.settings class="w-5 h-5 text-neutral-400" />
        </button>
        <button phx-click={@on_profile_click} class="w-8 h-8 rounded-full bg-neutral-700 flex items-center justify-center">
          <Lucideicons.user class="w-5 h-5 text-neutral-400" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders the storage quota banner.

  ## Examples

      <.quota_banner
        user_name="Maria"
        used_gb={45}
        total_gb={100}
        dismissable={true}
      />
  """
  attr :user_name, :string, required: true
  attr :used_gb, :integer, required: true
  attr :total_gb, :integer, required: true
  attr :dismissable, :boolean, default: true
  attr :on_dismiss, :string, default: nil

  def quota_banner(assigns) do
    assigns =
      assigns
      |> assign(:percentage, Float.round(assigns.used_gb / assigns.total_gb * 100, 1))
      |> assign(:warning_level, quota_warning_level(assigns.used_gb / assigns.total_gb * 100))

    ~H"""
    <div class="quota-banner mx-4">
      <div class="flex items-center justify-between mb-2">
        <h2 class="text-lg font-medium text-neutral-50">
          Olá, <%= @user_name %>! 👋
        </h2>
        <button
          :if={@dismissable and @percentage < 80}
          phx-click={@on_dismiss}
          class="text-neutral-400 hover:text-neutral-200 transition-colors"
        >
          <Lucideicons.x class="w-5 h-5" />
        </button>
      </div>

      <div class="quota-progress-bar mt-2">
        <div
          class={["quota-progress-fill", @warning_level]}
          style={"width: #{@percentage}%"}
        >
        </div>
      </div>

      <p class="text-body-sm text-neutral-400 mt-2">
        <%= @used_gb %> GB de <%= @total_gb %> GB usados
      </p>
    </div>
    """
  end

  @doc """
  Renders the bottom navigation bar.

  ## Examples

      <.bottom_nav
        active={:home}
        badges=%{ybira: 3, guara: 12}
      />
  """
  attr :active, :atom, required: true
  attr :badges, :map, default: %{}

  def bottom_nav(assigns) do
    ~H"""
    <nav class="bottom-nav">
      <.nav_item
        icon={:home}
        label="Home"
        service={:home}
        active={@active == :home}
        badge_count={Map.get(@badges, :home, 0)}
      />

      <.nav_item
        icon={:message_circle}
        label="Guará"
        service={:guara}
        active={@active == :guara}
        badge_count={Map.get(@badges, :guara, 0)}
        color="text-guara"
      />

      <.nav_item
        icon={:image}
        label="Jaci"
        service={:jaci}
        active={@active == :jaci}
        badge_count={Map.get(@badges, :jaci, 0)}
        color="text-jaci"
      />

      <.nav_item
        icon={:folder}
        label="Ybira"
        service={:ybira}
        active={@active == :ybira}
        badge_count={Map.get(@badges, :ybira, 0)}
        color="text-ybira"
      />

      <.nav_item
        icon={:settings}
        label="Config"
        service={:settings}
        active={@active == :settings}
        badge_count={0}
      />
    </nav>
    """
  end

  # Private navigation item component
  attr :icon, :atom, required: true
  attr :label, :string, required: true
  attr :service, :atom, required: true
  attr :active, :boolean, default: false
  attr :badge_count, :integer, default: 0
  attr :color, :string, default: "text-neutral-400"

  defp nav_item(assigns) do
    ~H"""
    <button
      phx-click={"navigate_to_#{@service}"}
      class="bottom-nav-item group"
    >
      <div class="relative">
        <%= case @icon do %>
          <% :home -> %>
            <Lucideicons.home class={["w-6 h-6", @active && @color || "text-neutral-400"]} />
          <% :message_circle -> %>
            <Lucideicons.message_circle class={["w-6 h-6", @active && @color || "text-neutral-400"]} />
          <% :image -> %>
            <Lucideicons.image class={["w-6 h-6", @active && @color || "text-neutral-400"]} />
          <% :folder -> %>
            <Lucideicons.folder class={["w-6 h-6", @active && @color || "text-neutral-400"]} />
          <% :settings -> %>
            <Lucideicons.settings class={["w-6 h-6", @active && @color || "text-neutral-400"]} />
        <% end %>
        <div :if={@badge_count > 0} class="bottom-nav-badge">
          <%= if @badge_count > 99, do: "99+", else: @badge_count %>
        </div>
      </div>
      <span class={[
        "text-caption mt-1",
        @active && "text-neutral-50 font-semibold",
        !@active && "text-neutral-400"
      ]}>
        <%= @label %>
      </span>
    </button>
    """
  end

  # Helper functions

  defp service_name(:ybira), do: "Ybira"
  defp service_name(:jaci), do: "Jaci"
  defp service_name(:guara), do: "Guará"

  defp service_description(:ybira), do: "Seus arquivos"
  defp service_description(:jaci), do: "Suas memórias"
  defp service_description(:guara), do: "Suas conversas"

  defp service_color(:ybira), do: "bg-ybira"
  defp service_color(:jaci), do: "bg-jaci"
  defp service_color(:guara), do: "bg-guara"

  defp quota_warning_level(percentage) when percentage >= 90, do: "quota-progress-fill-error"
  defp quota_warning_level(percentage) when percentage >= 80, do: "quota-progress-fill-warning"
  defp quota_warning_level(_), do: ""

  defp format_timestamp(timestamp) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, timestamp, :second)

    cond do
      diff < 60 -> "há #{diff} segundos"
      diff < 3600 -> "há #{div(diff, 60)} minutos"
      diff < 86_400 -> "há #{div(diff, 3600)} horas"
      diff < 172_800 -> "ontem"
      diff < 604_800 -> "há #{div(diff, 86_400)} dias"
      true -> Calendar.strftime(timestamp, "%d/%m/%Y")
    end
  end
end
