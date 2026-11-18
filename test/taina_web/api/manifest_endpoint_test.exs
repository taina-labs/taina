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
    assert is_nil(body["next_cursor"])
  end

  test "o ETag do conjunto inteiro: 304 quando o cliente ja tem", %{conn: conn, scope: scope} do
    {:ok, _file} = Ybira.upload(scope, tmp_upload_fixture("backup", "doc.txt"))

    first = get(conn, ~p"/api/v1/files/manifest")

    etag = Enum.find_value(first.resp_headers, fn {k, v} -> k == "etag" && v end)
    assert is_binary(etag) and byte_size(etag) > 0

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
    assert Enum.count_until(body["items"], 3) == 2
    assert is_binary(body["next_cursor"]) and byte_size(body["next_cursor"]) > 0

    # Teto alto pega tudo numa pagina so: sem cursor.
    body = conn |> get(~p"/api/v1/files/manifest", limit: "5000") |> json_response(200)
    assert Enum.count_until(body["items"], 4) == 3
    assert is_nil(body["next_cursor"])
  end

  test "default manifest stays readable while mirror includes own trash and excludes another owner's public file", %{
    conn: conn,
    scope: scope
  } do
    {:ok, own_live} = Ybira.upload(scope, tmp_upload_fixture("live", "live.txt"))
    {:ok, own_trash} = Ybira.upload(scope, tmp_upload_fixture("trash", "trash.txt"))
    {:ok, _} = Ybira.delete_file(scope, own_trash.rkey)
    {:ok, own_public} = Ybira.upload(scope, tmp_upload_fixture("own public", "own-public.txt"))
    {:ok, _} = Ybira.publicar_file(scope, own_public.rkey)

    other_scope = Scope.new(active_ava_fixture(scope.tekoa), scope.tekoa)
    {:ok, public} = Ybira.upload(other_scope, tmp_upload_fixture("public", "public.txt"))
    {:ok, _} = Ybira.publicar_file(other_scope, public.rkey)

    readable =
      conn
      |> get(~p"/api/v1/files/manifest")
      |> json_response(200)
      |> Map.fetch!("items")

    assert Enum.map(readable, & &1["rkey"]) == [own_live.rkey, own_public.rkey, public.rkey]

    mirror =
      conn
      |> get(~p"/api/v1/files/manifest", mode: "mirror")
      |> json_response(200)
      |> Map.fetch!("items")

    assert Enum.map(mirror, & &1["rkey"]) == [own_live.rkey, own_trash.rkey, own_public.rkey]
    assert Enum.at(mirror, 1)["deleted_at"]
  end

  test "mirror pagination and ETag track trash state", %{conn: conn, scope: scope} do
    {:ok, first_file} = Ybira.upload(scope, tmp_upload_fixture("first", "first.txt"))
    {:ok, second_file} = Ybira.upload(scope, tmp_upload_fixture("second", "second.txt"))

    first_page =
      conn
      |> get(~p"/api/v1/files/manifest", mode: "mirror", limit: "1")
      |> json_response(200)

    assert [first_item] = first_page["items"]
    assert first_item["rkey"] == first_file.rkey
    assert is_binary(first_page["next_cursor"]) and byte_size(first_page["next_cursor"]) > 0

    second_page =
      conn
      |> get(~p"/api/v1/files/manifest",
        mode: "mirror",
        limit: "1",
        after: first_page["next_cursor"]
      )
      |> json_response(200)

    assert [second_item] = second_page["items"]
    assert second_item["rkey"] == second_file.rkey
    assert is_nil(second_page["next_cursor"])

    initial = get(conn, ~p"/api/v1/files/manifest", mode: "mirror")
    initial_etag = Enum.find_value(initial.resp_headers, fn {key, value} -> key == "etag" && value end)

    {:ok, _} = Ybira.delete_file(scope, first_file.rkey)

    changed =
      conn
      |> put_req_header("if-none-match", initial_etag)
      |> get(~p"/api/v1/files/manifest", mode: "mirror")

    assert changed.status == 200
    changed_etag = Enum.find_value(changed.resp_headers, fn {key, value} -> key == "etag" && value end)
    assert changed_etag != initial_etag

    unchanged =
      conn
      |> put_req_header("if-none-match", changed_etag)
      |> get(~p"/api/v1/files/manifest", mode: "mirror")

    assert unchanged.status == 304
    assert unchanged.resp_body == ""
  end

  test "hash lookup returns the newest live duplicate before an older trash copy", %{conn: conn, scope: scope} do
    contents = "same bytes"
    {:ok, trashed} = Ybira.upload(scope, tmp_upload_fixture(contents, "older.txt"))
    {:ok, _} = Ybira.delete_file(scope, trashed.rkey)
    {:ok, _older_live} = Ybira.upload(scope, tmp_upload_fixture(contents, "older-live.txt"))
    {:ok, newest_live} = Ybira.upload(scope, tmp_upload_fixture(contents, "newer.txt"))

    body =
      conn
      |> get("/api/v1/files/by-hash/#{newest_live.hash}")
      |> json_response(200)

    assert body["status"] == "present"
    assert body["file"]["rkey"] == newest_live.rkey
    assert body["file"]["sha256"] == newest_live.hash
  end

  test "hash lookup reports trash and purge tombstones as suppressed", %{conn: conn, scope: scope} do
    {:ok, trashed} = Ybira.upload(scope, tmp_upload_fixture("trash", "trash.txt"))
    {:ok, _} = Ybira.delete_file(scope, trashed.rkey)

    trashed_body =
      conn
      |> get("/api/v1/files/by-hash/#{trashed.hash}")
      |> json_response(200)

    assert trashed_body == %{"status" => "suppressed", "file" => nil}

    {:ok, _} = Ybira.purge_trash_file(scope, trashed.rkey)

    purged_body =
      conn
      |> get("/api/v1/files/by-hash/#{trashed.hash}")
      |> json_response(200)

    assert purged_body == %{"status" => "suppressed", "file" => nil}
  end

  test "scheduled purge leaves a hash tombstone for lookup", %{conn: conn, scope: scope} do
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("scheduled", "scheduled.txt"))
    {:ok, _} = Ybira.delete_file(scope, file.rkey)
    cutoff = DateTime.shift(DateTime.utc_now(), day: 1)

    assert {:ok, 1} = Ybira.purge_deleted_files(cutoff)

    body =
      conn
      |> get("/api/v1/files/by-hash/#{file.hash}")
      |> json_response(200)

    assert body == %{"status" => "suppressed", "file" => nil}
  end

  test "unknown and other-owner hashes are not found, malformed hashes are validation errors", %{
    conn: conn,
    scope: scope
  } do
    other_scope = Scope.new(active_ava_fixture(scope.tekoa), scope.tekoa)
    {:ok, public} = Ybira.upload(other_scope, tmp_upload_fixture("other", "other.txt"))
    {:ok, _} = Ybira.publicar_file(other_scope, public.rkey)

    assert conn
           |> get("/api/v1/files/by-hash/#{public.hash}")
           |> json_response(404)
           |> get_in(["error", "code"]) == "not_found"

    assert conn
           |> get("/api/v1/files/by-hash/#{String.duplicate("0", 64)}")
           |> json_response(404)
           |> get_in(["error", "code"]) == "not_found"

    assert conn
           |> get("/api/v1/files/by-hash/#{String.duplicate("A", 64)}")
           |> json_response(422)
           |> get_in(["error", "code"]) == "validation_failed"
  end
end
