defmodule TainaWeb.TextPreviewTest do
  use ExUnit.Case, async: true

  alias TainaWeb.TextPreview

  test "valid UTF-8 text is preserved" do
    assert TextPreview.decode("café") == "café"
  end

  test "invalid non-UTF-8 bytes produce no preview" do
    assert TextPreview.decode(<<"caf", 0xE9, " na nuvem">>) == nil
    assert TextPreview.decode(<<0xFF, 0xE2>>) == nil
  end

  test "an incomplete trailing codepoint is dropped" do
    assert TextPreview.decode(<<"hello ", 0xE2, 0x82>>) == "hello "
  end
end
