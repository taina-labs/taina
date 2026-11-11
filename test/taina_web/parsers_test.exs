defmodule TainaWeb.ParsersTest do
  # The test changes global application upload configuration.
  use ExUnit.Case, async: false

  alias TainaWeb.Parsers

  test "reads the multipart limit when each request is parsed" do
    previous = Application.get_env(:taina, :upload)
    parser_opts = Parsers.init([])

    on_exit(fn ->
      if previous do
        Application.put_env(:taina, :upload, previous)
      else
        Application.delete_env(:taina, :upload)
      end
    end)

    Application.put_env(:taina, :upload, Keyword.put(previous || [], :max_blob_size, 1))

    body =
      "--boundary\r\n" <>
        "Content-Disposition: form-data; name=\"file\"\r\n\r\n" <>
        String.duplicate("a", 1_048_578) <>
        "\r\n--boundary--\r\n"

    conn =
      :post
      |> Plug.Test.conn("/upload", body)
      |> Plug.Conn.put_req_header("content-type", "multipart/form-data; boundary=boundary")

    assert_raise Plug.Parsers.RequestTooLargeError, fn ->
      Parsers.call(conn, parser_opts)
    end
  end
end
