defmodule TainaWeb.HealthControllerTest do
  use TainaWeb.ConnCase, async: false

  test "GET /health returns ok when the database responds", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert %{"status" => "ok", "database" => "ok"} = json_response(conn, 200)
  end
end
