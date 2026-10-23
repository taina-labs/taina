defmodule Ypy.VarintTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Ypy.Varint

  test "encodes the known vectors" do
    assert Varint.encode(300) == <<0xAC, 0x02>>
    assert Varint.encode(0) == <<0x00>>
    assert Varint.encode(127) == <<0x7F>>
    assert Varint.encode(128) == <<0x80, 0x01>>
  end

  test "round trips" do
    for n <- [0, 1, 127, 128, 300, 65_535, 1 <<< 32, 1 <<< 63] do
      assert Varint.decode(Varint.encode(n)) == {n, ""}
    end
  end

  test "decode returns the rest of the binary" do
    assert Varint.decode(<<0xAC, 0x02, 0xFF>>) == {300, <<0xFF>>}
    assert Varint.decode(<<0x7F, 0x01, 0x02>>) == {127, <<0x01, 0x02>>}
  end
end
