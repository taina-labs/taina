defmodule Ypy.Base32Test do
  use ExUnit.Case, async: true

  alias Ypy.Base32

  @alphabet ~c"abcdefghijklmnopqrstuvwxyz234567"

  test "round trips binaries" do
    for bin <- [
          <<>>,
          <<0>>,
          <<1>>,
          <<0, 1, 2, 3, 4>>,
          :crypto.strong_rand_bytes(32),
          :crypto.strong_rand_bytes(7),
          :crypto.strong_rand_bytes(64)
        ] do
      assert Base32.decode!(Base32.encode(bin)) == bin
    end
  end

  test "encodes lowercase, unpadded, using only the rfc 4648 alphabet" do
    out = Base32.encode(:crypto.strong_rand_bytes(32))

    refute String.contains?(out, "=")
    assert out == String.downcase(out)

    for c <- String.to_charlist(out) do
      assert c in @alphabet
    end
  end

  test "a five byte value is an exact fit" do
    assert String.length(Base32.encode(<<1, 2, 3, 4, 5>>)) == 8
    assert Base32.decode!(Base32.encode(<<1, 2, 3, 4, 5>>)) == <<1, 2, 3, 4, 5>>
  end

  test "decodes the short forms" do
    assert Base32.decode!("aaaaa") == <<0, 0, 0>>
    assert Base32.decode!("aa") == <<0>>
    assert Base32.decode!("") == <<>>
  end

  test "decode! raises on a character outside the alphabet" do
    assert_raise ArgumentError, "invalid base32 character: 1", fn ->
      Base32.decode!("abc1def")
    end

    assert_raise ArgumentError, fn -> Base32.decode!("A") end
    assert_raise ArgumentError, fn -> Base32.decode!("0189") end
  end

  test "decode! raises on non-zero padding bits" do
    assert_raise ArgumentError, "non-zero base32 padding bits", fn ->
      Base32.decode!("mzxw7")
    end
  end
end
