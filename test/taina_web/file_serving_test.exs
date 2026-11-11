defmodule TainaWeb.FileServingTest do
  use ExUnit.Case, async: true

  alias TainaWeb.FileServing

  setup do
    path = Path.join(System.tmp_dir!(), "file_serving_#{System.unique_integer([:positive])}")
    # The path is generated under the OS temp directory for this test.
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    File.write!(path, "image bytes")
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "serves SVG as an attachment with nosniff", %{path: path} do
    conn = serve(path, "image/svg+xml", "image.svg")

    assert conn.status == 200
    assert [content_disposition] = Plug.Conn.get_resp_header(conn, "content-disposition")
    assert String.starts_with?(content_disposition, "attachment;")
    assert Plug.Conn.get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  test "keeps allowed image previews inline with nosniff", %{path: path} do
    conn = serve(path, "image/png", "image.png")

    assert conn.status == 200
    assert [content_disposition] = Plug.Conn.get_resp_header(conn, "content-disposition")
    assert String.starts_with?(content_disposition, "inline;")
    assert Plug.Conn.get_resp_header(conn, "x-content-type-options") == ["nosniff"]
  end

  defp serve(path, mime, name) do
    file = %{mime: mime, nome: name, tamanho: 11, updated_at: nil}
    conn = Plug.Test.conn(:get, "/files/#{name}")
    FileServing.serve(conn, file, path)
  end
end
