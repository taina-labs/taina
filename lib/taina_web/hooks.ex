defmodule TainaWeb.Hooks do
  @moduledoc """
  `on_mount` compartilhado do shell autenticado: estatísticas de armazenamento
  para o mini-card da sidebar e o ponto de "tem pedido esperando" na aba Conta,
  calculados uma vez por mount (`assign_new` evita reconsulta na passagem
  HTTP -> WebSocket).

  Inscreve-se uma vez no tópico de eventos do Ava (RFC_003 D4) quando conectado;
  cada LiveView trata só as mensagens da sua tela e ignora o resto. O ponto não é
  ao vivo entre abas: recomputa no próximo mount/navegação.
  """

  import Phoenix.Component, only: [assign_new: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias Taina.Maraca
  alias Taina.Ybira

  def on_mount(:shell, _params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) and scope, do: Maraca.subscribe_to_my_events(scope.ava)

    socket =
      socket
      |> assign_new(:storage_stats, fn -> load_storage_stats(scope) end)
      |> assign_new(:account_alert, fn -> account_alert?(scope) end)

    {:cont, socket}
  end

  defp load_storage_stats(nil), do: nil

  defp load_storage_stats(scope) do
    case Ybira.storage_stats(scope) do
      {:ok, stats} -> stats
      _error -> nil
    end
  end

  # Ponto na aba Conta quando há pedido a decidir (caixa do dono) ou pedido feito
  # ainda aguardando (visão de quem pediu). Recomputado a cada mount/navegação.
  defp account_alert?(nil), do: false

  defp account_alert?(scope) do
    Maraca.list_access_requests(scope.ava) != [] or Maraca.list_my_requests(scope.ava) != []
  end
end
