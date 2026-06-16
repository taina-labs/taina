defmodule TainaWeb.Hooks do
  @moduledoc """
  `on_mount` compartilhado do shell autenticado: estatísticas de armazenamento
  para o mini-card da sidebar, calculadas uma vez por mount (`assign_new` evita
  reconsulta na passagem HTTP -> WebSocket).
  """

  import Phoenix.Component, only: [assign_new: 3]

  alias Taina.Ybira

  def on_mount(:shell, _params, _session, socket) do
    socket = assign_new(socket, :storage_stats, fn -> load_storage_stats(socket.assigns.current_scope) end)

    {:cont, socket}
  end

  defp load_storage_stats(nil), do: nil

  defp load_storage_stats(scope) do
    case Ybira.storage_stats(scope) do
      {:ok, stats} -> stats
      _error -> nil
    end
  end
end
