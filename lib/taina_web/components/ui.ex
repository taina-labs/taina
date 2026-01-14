defmodule TainaWeb.Components.UI do
  @moduledoc """
  Basic UI components for Tainá with built-in styling.
  These are foundational components used across all services.
  """
  use Phoenix.Component

  @doc """
  Renders a badge for notifications.
  Styled with Tainá design system colors.
  """
  attr :count, :integer, required: true
  attr :color, :string, default: "bg-red-600"

  def badge(assigns) do
    ~H"""
    <div
      :if={@count > 0}
      class={["w-6 h-6 rounded-full flex items-center justify-center text-xs font-semibold text-white", @color]}
    >
      <%= if @count > 99, do: "99+", else: @count %>
    </div>
    """
  end

  @doc """
  Renders flash notices with Tainá styling.
  """
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error, :success]

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      class={[
        "fixed bottom-20 left-4 right-4 px-4 py-3 rounded-lg shadow-lg z-50",
        "animate-slide-up",
        @kind == :info && "bg-blue-800 border-l-4 border-blue-500",
        @kind == :success && "bg-green-800 border-l-4 border-green-500",
        @kind == :error && "bg-red-800 border-l-4 border-red-500"
      ]}
    >
      <p class="text-white text-body-md"><%= msg %></p>
    </div>
    """
  end

  @doc """
  Renders a skeleton loader for loading states.
  """
  attr :class, :string, default: ""
  attr :height, :string, default: "h-24"

  def skeleton(assigns) do
    ~H"""
    <div class={["skeleton rounded-xl", @height, @class]}></div>
    """
  end
end
