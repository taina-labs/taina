defmodule TainaWeb.FileThumbnailTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Ybira

  @moduletag capture_log: true

  setup do
    scope = scope_fixture()
    {:ok, photo} = Ybira.upload(scope, tmp_image_fixture(filename: "p.jpg"))
    {:ok, photo} = Ybira.get_file(scope, photo.public_id)
    %{ava: scope.ava, photo: photo}
  end

  test "serves a generated thumbnail as webp", %{conn: conn, ava: ava, photo: photo} do
    conn = conn |> log_in(ava) |> get(~p"/files/#{photo.public_id}/thumbnail/sm")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/webp"]
  end

  test "404 for an unsupported size", %{conn: conn, ava: ava, photo: photo} do
    conn = conn |> log_in(ava) |> get(~p"/files/#{photo.public_id}/thumbnail/xl")

    assert conn.status == 404
  end

  test "401 without a session", %{conn: conn, photo: photo} do
    conn = get(conn, ~p"/files/#{photo.public_id}/thumbnail/sm")

    assert conn.status == 401
  end
end
