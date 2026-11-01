defmodule TainaWeb.InternalPathTest do
  use ExUnit.Case, async: true

  alias TainaWeb.InternalPath

  test "accepts an internal path and query string" do
    assert InternalPath.return_to("/galeria/linha-do-tempo?zona=casa", "/") ==
             "/galeria/linha-do-tempo?zona=casa"
  end

  test "uses the fallback for external, protocol-relative, and malformed paths" do
    for value <- [
          "https://example.com/path",
          "//example.com/path",
          "///example.com",
          "/\\example.com",
          "/%zz",
          "relative/path"
        ] do
      assert InternalPath.return_to(value, "/moradores") == "/moradores"
    end
  end

  test "extracts path and query from the current URI" do
    assert InternalPath.from_uri("https://taina.local/galeria?zona=praca") == "/galeria?zona=praca"
  end
end
