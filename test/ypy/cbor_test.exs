defmodule Ypy.CborTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Ypy.Cbor
  alias Ypy.Cbor.Bytes

  test "encodes the known vectors" do
    assert Cbor.encode(%{"a" => 1}) == <<0xA1, 0x61, 0x61, 0x01>>

    assert Cbor.encode(%{"bb" => 1, "a" => 2}) ==
             <<0xA2, 0x61, 0x61, 0x02, 0x62, 0x62, 0x62, 0x01>>
  end

  test "sorts map keys by length first, then bytewise" do
    assert Cbor.encode(%{"ccc" => 1, "dd" => 2}) ==
             <<0xA2, 0x62, 0x64, 0x64, 0x02, 0x63, 0x63, 0x63, 0x63, 0x01>>

    assert Cbor.encode(%{"b" => 1, "a" => 2}) ==
             <<0xA2, 0x61, 0x61, 0x02, 0x61, 0x62, 0x01>>
  end

  test "encodes simple values" do
    assert Cbor.encode(nil) == <<0xF6>>
    assert Cbor.encode(true) == <<0xF5>>
    assert Cbor.encode(false) == <<0xF4>>
    assert Cbor.encode(%{}) == <<0xA0>>
    assert Cbor.encode([]) == <<0x80>>
  end

  test "encodes integers with the shortest head" do
    assert Cbor.encode(23) == <<0x17>>
    assert Cbor.encode(24) == <<0x18, 0x18>>
    assert Cbor.encode(255) == <<0x18, 0xFF>>
    assert Cbor.encode(256) == <<0x19, 0x01, 0x00>>
    assert Cbor.encode(65_535) == <<0x19, 0xFF, 0xFF>>
    assert Cbor.encode(65_536) == <<0x1A, 0x00, 0x01, 0x00, 0x00>>
    assert Cbor.encode(4_294_967_296) == <<0x1B, 0, 0, 0, 1, 0, 0, 0, 0>>
    assert Cbor.encode(-1) == <<0x20>>
    assert Cbor.encode(-500) == <<0x39, 0x01, 0xF3>>
  end

  test "encodes floats as 64 bit" do
    assert Cbor.encode(1.5) == <<0xFB, 0x3F, 0xF8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>
    assert Cbor.encode(0.0) == <<0xFB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00>>
  end

  test "encodes text strings and byte strings distinctly" do
    assert Cbor.encode("hi") == <<0x62, 0x68, 0x69>>
    assert Cbor.encode(%Bytes{data: <<1, 2, 3>>}) == <<0x43, 1, 2, 3>>
    assert Cbor.encode(%Bytes{data: <<0xFF, 0xFE>>}) == <<0x42, 0xFF, 0xFE>>
    assert Cbor.encode([1, 2]) == <<0x82, 0x01, 0x02>>
  end

  test "round trips every supported term" do
    for term <- [
          nil,
          true,
          false,
          0,
          -1,
          -500,
          23,
          24,
          255,
          256,
          65_535,
          65_536,
          4_294_967_296,
          0xFFFF_FFFF_FFFF_FFFF,
          1.5,
          "hi",
          %Bytes{data: <<1, 2, 3>>},
          %Bytes{data: <<0xFF, 0xFE>>},
          [],
          [1, "two", nil],
          %{},
          %{"a" => 1},
          %{"bb" => 1, "a" => 2},
          %{"m" => [1, "two", nil], "b" => %Bytes{data: <<1, 2, 3>>}}
        ] do
      assert term |> Cbor.encode() |> Cbor.decode!() == term
    end
  end

  test "decode returns the rest of the binary" do
    assert Cbor.decode(<<0xA1, 0x61, 0x61, 0x01, 0xFF>>) == {%{"a" => 1}, <<0xFF>>}
  end

  test "encode rejects a map with non-string keys" do
    assert_raise ArgumentError, "map keys must be strings, got: 1", fn ->
      Cbor.encode(%{1 => 2})
    end
  end

  test "encode rejects invalid utf-8 in a text string" do
    assert_raise ArgumentError, "text strings must be valid UTF-8", fn ->
      Cbor.encode(<<0xFF, 0xFE>>)
    end
  end

  test "encode rejects unencodable terms" do
    assert_raise ArgumentError, "not encodable as DAG-CBOR: :atom", fn ->
      Cbor.encode(:atom)
    end

    assert_raise ArgumentError, fn -> Cbor.encode({1, 2}) end
    assert_raise ArgumentError, fn -> Cbor.encode(self()) end
    assert_raise ArgumentError, fn -> Cbor.encode(1 <<< 64) end
  end

  describe "decode strictness" do
    test "rejects indefinite-length items" do
      assert_raise ArgumentError,
                   "indefinite-length items are not valid DAG-CBOR",
                   fn -> Cbor.decode!(<<0xBF, 0xFF>>) end

      assert_raise ArgumentError, fn -> Cbor.decode!(<<0x5F, 0xFF>>) end
      assert_raise ArgumentError, fn -> Cbor.decode!(<<0x7F, 0xFF>>) end
      assert_raise ArgumentError, fn -> Cbor.decode!(<<0x9F, 0xFF>>) end
    end

    test "rejects 16-bit floats" do
      assert_raise ArgumentError, "16-bit floats are not valid DAG-CBOR", fn ->
        Cbor.decode!(<<0xF9, 0x00, 0x00>>)
      end
    end

    test "rejects tags other than 42" do
      assert_raise ArgumentError, "unsupported tag: 1", fn ->
        Cbor.decode!(<<0xC1, 0x00>>)
      end

      assert_raise ArgumentError, fn -> Cbor.decode!(<<0xD8, 0x2B, 0x00>>) end
    end

    test "rejects a map key that is not a string" do
      assert_raise ArgumentError, "map keys must be strings", fn ->
        Cbor.decode!(<<0xA1, 0x01, 0x01>>)
      end
    end

    test "rejects invalid utf-8 in a text string" do
      assert_raise ArgumentError, "invalid UTF-8 in text string", fn ->
        Cbor.decode!(<<0x62, 0xFF, 0xFE>>)
      end
    end
  end
end
