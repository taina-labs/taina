defmodule TainaWeb.API.ManifestEndpointTest do
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

  test "o manifesto lista com a forma completa do arquivo", %{conn: conn, scope: scope} do
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("backup", "doc.txt"))

    body = conn |> get(~p"/api/v1/files/manifest") |> json_response(200)

    assert [item] = body["items"]
    assert item["rkey"] == file.rkey
    assert item["sha256"] == file.hash
    assert item["name"] == "doc.txt"
    assert body["next_cursor"] == nil
  end

  test "o ETag do conjunto inteiro: 304 quando o cliente ja tem", %{conn: conn, scope: scope} do
    {:ok, _file} = Ybira.upload(scope, tmp_upload_fixture("backup", "doc.txt"))

    first = get(conn, ~p"/api/v1/files/manifest")

    etag = Enum.find_value(first.resp_headers, fn {k, v} -> k == "etag" && v end)
    assert is_binary(etag)

    response = conn |> put_req_header("if-none-match", etag) |> get(~p"/api/v1/files/manifest")
    assert response.status == 304
    assert response.resp_body == ""
  end

  test "limit com teto proprio (200 padrao, 1000 no maximo)", %{conn: conn, scope: scope} do
    {:ok, _a} = Ybira.upload(scope, tmp_upload_fixture("1", "a.txt"))
    {:ok, _b} = Ybira.upload(scope, tmp_upload_fixture("2", "b.txt"))
    {:ok, _c} = Ybira.upload(scope, tmp_upload_fixture("3", "c.txt"))

    # Pagina cheia (2 de 3): o cursor aponta para a proxima.
    body = conn |> get(~p"/api/v1/files/manifest", limit: "2") |> json_response(200)
    assert length(body["items"]) == 2
    assert is_binary(body["next_cursor"])

    # Teto alto pega tudo numa pagina so: sem cursor.
    body = conn |> get(~p"/api/v1/files/manifest", limit: "5000") |> json_response(200)
    assert length(body["items"]) == 3
    assert body["next_cursor"] == nil
  end
end
