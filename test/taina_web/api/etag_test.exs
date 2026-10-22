defmodule TainaWeb.API.EtagTest do
  use TainaWeb.ConnCase, async: true

  import Plug.Conn

  alias TainaWeb.API.Etag

  test "o token leva a contagem e o unix do maior updated_at" do
    at = ~U[2026-10-20 12:30:00Z]

    assert Etag.token(0, nil) == ~s(W/"0-0")
    assert Etag.token(3, at) == ~s(W/"3-#{DateTime.to_unix(at)}")
  end

  test "sem If-None-Match, a listagem segue com o ETag anotado" do
    {:fresh, conn} = Etag.handle(build_conn(), ~s(W/"3-10"))

    assert get_resp_header(conn, "etag") == [~s(W/"3-10")]
  end

  test "If-None-Match igual responde 304 sem corpo, com o ETag na resposta" do
    conn = build_conn() |> put_req_header("if-none-match", ~s(W/"3-10"))

    {:not_modified, conn} = Etag.handle(conn, ~s(W/"3-10"))

    assert conn.status == 304
    assert conn.resp_body == ""
    assert get_resp_header(conn, "etag") == [~s(W/"3-10")]
  end

  test "ETag diferente nao bate: a listagem segue" do
    conn = build_conn() |> put_req_header("if-none-match", ~s(W/"9-99"))

    assert {:fresh, _conn} = Etag.handle(conn, ~s(W/"3-10"))
  end
end
