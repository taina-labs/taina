defmodule TainaWeb.HealthController do
  use TainaWeb, :controller

  alias Ecto.Adapters.SQL

  def show(conn, _params) do
    case SQL.query(Taina.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok", database: "ok"})

      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "degraded", database: "error"})
    end
  end
end
