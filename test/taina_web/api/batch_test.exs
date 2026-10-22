defmodule TainaWeb.API.BatchTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  @moduletag capture_log: true

  setup do
    tekoa = tekoa_fixture()
    dono = active_ava_fixture(tekoa)

    %{
      scope: Scope.new(dono, tekoa),
      conn: authorize_device(build_conn(), dono)
    }
  end

  defp upload(conn) do
    conn
    |> post(~p"/api/v1/files", %{"file" => upload(tmp_upload_fixture("x", "a.txt"), "a.txt")})
    |> json_response(201)
  end

  defp upload(path, filename) do
    %Plug.Upload{path: path, filename: filename, content_type: "text/plain"}
  end

  test "lixeira e volta em lote, um resultado por id", %{conn: conn, scope: scope} do
    a = upload(conn)
    b = upload(conn)
    folder = conn |> post(~p"/api/v1/folders", %{"name" => "Destino"}) |> json_response(201)

    body =
      conn
      |> post(~p"/api/v1/files/batch", %{"op" => "trash", "ids" => [a["rkey"], b["rkey"]]})
      |> json_response(200)

    assert [%{"rkey" => primeiro_rkey, "ok" => true}, %{"rkey" => segundo_rkey, "ok" => true}] =
             body["results"]

    assert primeiro_rkey == a["rkey"]
    assert segundo_rkey == b["rkey"]

    assert %{"file" => file} = hd(body["results"])
    assert file["deleted_at"] != nil

    body =
      conn
      |> post(~p"/api/v1/files/batch", %{
        "op" => "move",
        "ids" => [b["rkey"]],
        "folder" => folder["rkey"]
      })
      |> json_response(200)

    assert [%{"rkey" => rkey_movido, "ok" => true, "file" => file}] = body["results"]
    assert rkey_movido == b["rkey"]
    assert file["folder"] == folder["rkey"]

    body =
      conn
      |> post(~p"/api/v1/files/batch", %{"op" => "restore", "ids" => [a["rkey"]]})
      |> json_response(200)

    assert [%{"rkey" => rkey_restaurado, "ok" => true, "file" => file}] = body["results"]
    assert rkey_restaurado == a["rkey"]
    assert file["deleted_at"] == nil

    assert Ybira.get_file(scope, a["rkey"]) |> elem(0) == :ok
  end

  test "a falha de um id nao para o lote", %{conn: conn} do
    a = upload(conn)

    body =
      conn
      |> post(~p"/api/v1/files/batch", %{"op" => "trash", "ids" => [a["rkey"], "zzzzzzzzzzzzz"]})
      |> json_response(200)

    assert [%{"ok" => true}, %{"ok" => false, "error" => "not_found"}] = body["results"]
  end

  test "op desconhecida responde 422 invalid_action", %{conn: conn} do
    body =
      conn
      |> post(~p"/api/v1/files/batch", %{"op" => "explodir", "ids" => ["zzzzzzzzzzzzz"]})
      |> json_response(422)

    assert body["error"]["code"] == "invalid_action"
  end

  test "ids acima do teto de 200 responde 422 validation_failed", %{conn: conn} do
    ids = Enum.map(1..201, &Integer.to_string/1)

    body =
      conn
      |> post(~p"/api/v1/files/batch", %{"op" => "trash", "ids" => ids})
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end

  test "ids que nao sao lista responde 422", %{conn: conn} do
    body =
      conn
      |> post(~p"/api/v1/files/batch", %{"op" => "trash", "ids" => "a.txt"})
      |> json_response(422)

    assert body["error"]["code"] == "validation_failed"
  end
end
