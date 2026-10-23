defmodule Ypy.Maraca.KeysTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ypy.Base58
  alias Ypy.Maraca.Keys
  alias Ypy.Secp256k1

  @curve_order 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  test "generate derives the compressed generator point from entropy 1" do
    {pub, priv} = Keys.generate(<<1::256>>)

    assert priv == <<1::256>>

    assert pub ==
             <<0x02, 0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798::256>>
  end

  test "generate accepts the largest valid entropy" do
    {pub, priv} = Keys.generate(<<@curve_order - 1::256>>)

    assert byte_size(pub) == 33
    assert priv == <<@curve_order - 1::256>>
  end

  test "generate raises on zero entropy and on the curve order" do
    assert_raise ArgumentError, fn -> Keys.generate(<<0::256>>) end
    assert_raise ArgumentError, fn -> Keys.generate(<<@curve_order::256>>) end
  end

  test "generate requires 32 bytes of entropy" do
    assert_raise FunctionClauseError, fn -> Keys.generate(<<1::128>>) end
  end

  test "public_key_multibase is a z Multikey over the multicodec prefix" do
    {pub, _priv} = Keys.generate(:crypto.strong_rand_bytes(32))
    multibase = Keys.public_key_multibase(pub)

    assert <<?z, rest::binary>> = multibase
    assert Base58.decode!(rest) == <<0xE7, 0x01>> <> pub
  end

  test "verify accepts the signature the private key produced" do
    {pub, priv} = Keys.generate(:crypto.strong_rand_bytes(32))
    sig = Secp256k1.sign(priv, "registro da tekoa")

    assert Keys.verify(pub, sig, "registro da tekoa")
    refute Keys.verify(pub, sig, "outro registro")
  end

  test "verify rejects a tampered signature" do
    {pub, priv} = Keys.generate(:crypto.strong_rand_bytes(32))
    sig = Secp256k1.sign(priv, "payload")
    <<r::binary-32, s::binary-32>> = sig

    refute Keys.verify(pub, s <> r, "payload")
  end

  test "verify answers false for a malformed public point instead of crashing" do
    {_pub, priv} = Keys.generate(:crypto.strong_rand_bytes(32))
    sig = Secp256k1.sign(priv, "payload")

    refute Keys.verify(:crypto.strong_rand_bytes(33), sig, "payload")
    refute Keys.verify(<<2>> <> :crypto.strong_rand_bytes(32), sig, "payload")
  end

  test "fingerprint is deterministic and 16 base32 characters" do
    {pub, _priv} = Keys.generate(:crypto.strong_rand_bytes(32))
    fingerprint = Keys.fingerprint(pub)

    assert String.length(fingerprint) == 16
    assert fingerprint == Keys.fingerprint(pub)
    assert String.downcase(fingerprint) == fingerprint
  end

  property "sign and verify roundtrip over random entropies and payloads" do
    check all(
            payload <- StreamData.binary(max_length: 128),
            entropy <- StreamData.binary(length: 32),
            max_runs: 20
          ) do
      {pub, priv} = Keys.generate(entropy)
      sig = Secp256k1.sign(priv, payload)

      assert Keys.verify(pub, sig, payload)
      refute Keys.verify(pub, sig, payload <> "!")
    end
  end
end
