defmodule Ypy.CborCidInteropTest do
  use ExUnit.Case, async: true

  alias Ypy.Cbor
  alias Ypy.Cid

  test "a cid value encodes as tag 42 over a 0x00 prefixed byte string" do
    cid = Cid.from_data(<<1, 2>>)
    payload = Cid.to_bytes(cid)

    assert Cbor.encode(%{"l" => cid}) ==
             <<0xA1, 0x61, 0x6C, 0xD8, 0x2A, 0x58, byte_size(payload) + 1, 0x00>> <> payload
  end

  test "a cid value decodes back to an equal struct" do
    cid = Cid.from_data(<<1, 2, 3>>)
    term = %{"l" => cid, "n" => 1}

    assert term |> Cbor.encode() |> Cbor.decode!() == term
  end

  test "a bare cid round trips" do
    cid = Cid.from_data(<<1, 2, 3>>, Cid.raw())

    assert cid |> Cbor.encode() |> Cbor.decode!() == cid
  end

  test "a cid nested in a list round trips" do
    cid = Cid.from_data(<<9>>)
    term = [%{"ref" => cid}]

    assert term |> Cbor.encode() |> Cbor.decode!() == term
  end

  test "re-encoding a decoded record reproduces the same bytes" do
    data = Cbor.encode(%{"ref" => Cid.from_data(<<1>>), "a" => 1})

    assert data |> Cbor.decode!() |> Cbor.encode() == data
  end
end
