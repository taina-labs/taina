defmodule TainaWeb.FileThumbnailTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  @moduletag capture_log: true

  setup do
    tekoa = tekoa_fixture()
    owner = Scope.new(active_ava_fixture(tekoa), tekoa)
    other = Scope.new(active_ava_fixture(tekoa), tekoa)
    {:ok, photo} = Ybira.upload(owner, tmp_image_fixture(filename: "p.jpg"))
    {:ok, photo} = Ybira.get_file(owner, photo.rkey)
    %{owner: owner, other: other, ava: owner.ava, photo: photo}
  end

  test "serves a generated thumbnail as webp", %{conn: conn, ava: ava, photo: photo} do
    conn = conn |> log_in(ava) |> get(~p"/files/#{photo.rkey}/thumbnail/sm")

    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/webp"]
    assert get_resp_header(conn, "cache-control") == ["private, max-age=86400"]
  end

  test "404 for an unsupported size", %{conn: conn, ava: ava, photo: photo} do
    conn = conn |> log_in(ava) |> get(~p"/files/#{photo.rkey}/thumbnail/xl")

    assert conn.status == 404
  end

  test "redirects to login without a session", %{conn: conn, photo: photo} do
    conn = get(conn, ~p"/files/#{photo.rkey}/thumbnail/sm")

    assert redirected_to(conn, 302) == "/login"
  end

  test "redirects another resident's casa thumbnail to the file screen, then 200 once published", %{
    owner: owner,
    other: other,
    photo: photo
  } do
    conn = build_conn() |> log_in(other.ava) |> get(~p"/files/#{photo.rkey}/thumbnail/sm")
    assert redirected_to(conn, 302) == "/arquivos/#{photo.rkey}"

    {:ok, _} = Ybira.publicar_file(owner, photo.rkey)

    conn = build_conn() |> log_in(other.ava) |> get(~p"/files/#{photo.rkey}/thumbnail/sm")
    assert conn.status == 200
    assert get_resp_header(conn, "content-type") == ["image/webp"]
  end
end
