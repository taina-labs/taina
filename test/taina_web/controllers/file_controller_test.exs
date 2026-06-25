defmodule TainaWeb.FileControllerTest do
  use TainaWeb.ConnCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  @contents "conteudo do arquivo para download"

  setup do
    tekoa = tekoa_fixture()
    owner = Scope.new(active_ava_fixture(tekoa), tekoa)
    other = Scope.new(active_ava_fixture(tekoa), tekoa)
    {:ok, ybira_file} = Ybira.upload(owner, tmp_upload_fixture(@contents, "a.txt"))
    %{owner: owner, other: other, ava: owner.ava, ybira_file: ybira_file}
  end

  defp authed(conn, ava), do: log_in(conn, ava)

  test "serves the full ybira_file with 200 and accept-ranges", %{conn: conn, ava: ava, ybira_file: ybira_file} do
    conn = conn |> authed(ava) |> get(~p"/files/#{ybira_file.public_id}")

    assert conn.status == 200
    assert response(conn, 200) == @contents
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "content-type") == [ybira_file.mime_type]

    assert get_resp_header(conn, "content-disposition") == [
             ~s(attachment; filename="#{ybira_file.original_filename}")
           ]
  end

  test "serves a byte range with 206 and content-range", %{conn: conn, ava: ava, ybira_file: ybira_file} do
    conn =
      conn
      |> authed(ava)
      |> put_req_header("range", "bytes=0-4")
      |> get(~p"/files/#{ybira_file.public_id}")

    assert conn.status == 206
    assert response(conn, 206) == binary_part(@contents, 0, 5)
    assert get_resp_header(conn, "content-range") == ["bytes 0-4/#{ybira_file.file_size_bytes}"]
  end

  test "answers 416 for an unsatisfiable range", %{conn: conn, ava: ava, ybira_file: ybira_file} do
    conn =
      conn
      |> authed(ava)
      |> put_req_header("range", "bytes=999999-")
      |> get(~p"/files/#{ybira_file.public_id}")

    assert conn.status == 416
    assert get_resp_header(conn, "content-range") == ["bytes */#{ybira_file.file_size_bytes}"]
  end

  test "401 without a session", %{conn: conn, ybira_file: ybira_file} do
    conn = get(conn, ~p"/files/#{ybira_file.public_id}")

    assert conn.status == 401
  end

  test "404 for an unknown ybira_file", %{conn: conn, ava: ava} do
    conn = conn |> authed(ava) |> get(~p"/files/desconhecido1")

    assert conn.status == 404
  end

  test "403 for another resident's casa file", %{conn: conn, other: other, ybira_file: ybira_file} do
    conn = conn |> authed(other.ava) |> get(~p"/files/#{ybira_file.public_id}")

    assert conn.status == 403
  end

  test "200 once the file is published to the praca", %{
    conn: conn,
    owner: owner,
    other: other,
    ybira_file: ybira_file
  } do
    {:ok, _} = Ybira.publicar_file(owner, ybira_file.public_id)

    conn = conn |> authed(other.ava) |> get(~p"/files/#{ybira_file.public_id}")

    assert conn.status == 200
    assert response(conn, 200) == @contents
  end

  test "200 for the owner's own casa file (no lockout)", %{conn: conn, ava: ava, ybira_file: ybira_file} do
    conn = conn |> authed(ava) |> get(~p"/files/#{ybira_file.public_id}")

    assert conn.status == 200
    assert response(conn, 200) == @contents
  end
end
