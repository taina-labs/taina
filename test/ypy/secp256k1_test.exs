defmodule Ypy.Secp256k1Test do
  use ExUnit.Case, async: true

  alias Ypy.Base58
  alias Ypy.Secp256k1

  @group_order 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  defp uncompressed_pub(priv) do
    {pub, ^priv} = :crypto.generate_key(:ecdh, :secp256k1, priv)
    pub
  end

  defp verifies?(priv, payload) do
    der = Secp256k1.raw_to_der(Secp256k1.sign(priv, payload))
    :crypto.verify(:ecdsa, :sha256, payload, der, [uncompressed_pub(priv), :secp256k1])
  end

  test "generate_keypair returns a 33-byte compressed public key" do
    {pub, priv} = Secp256k1.generate_keypair()

    assert byte_size(pub) == 33
    assert <<prefix, _rest::binary-32>> = pub
    assert prefix in [0x02, 0x03]
    assert byte_size(priv) == 32
  end

  test "public_from_private re-derives the compressed public key" do
    {pub, priv} = Secp256k1.generate_keypair()

    assert Secp256k1.public_from_private(priv) == pub
  end

  test "compress picks the prefix from the parity of y" do
    for _i <- 1..5 do
      {_pub_u, priv} = :crypto.generate_key(:ecdh, :secp256k1)
      <<4, x::binary-32, y::binary-32>> = uncompressed_pub(priv)
      y_odd = rem(:binary.decode_unsigned(y), 2) == 1

      assert <<prefix, ^x::binary>> = Secp256k1.compress(<<4, x::binary, y::binary>>)
      assert prefix == if(y_odd, do: 0x03, else: 0x02)
    end
  end

  test "public_key_multibase is a z-prefixed base58btc multikey" do
    {pub, _priv} = Secp256k1.generate_keypair()
    multibase = Secp256k1.public_key_multibase(pub)

    assert <<?z, rest::binary>> = multibase
    assert Base58.decode!(rest) == <<0xE7, 0x01>> <> pub
  end

  test "sign returns a 64-byte raw signature that verifies" do
    {pub, priv} = Secp256k1.generate_keypair()
    sig = Secp256k1.sign(priv, "the payload")

    assert byte_size(sig) == 64
    assert verifies?(priv, "the payload")
    assert Secp256k1.public_from_private(priv) == pub
  end

  test "sign normalizes S to the low half of the group order" do
    {_pub, priv} = Secp256k1.generate_keypair()

    for payload <- ["a", "b", "hello world", <<0, 1, 2, 3>>, :crypto.strong_rand_bytes(64)] do
      <<_r::binary-32, s::binary-32>> = Secp256k1.sign(priv, payload)
      assert :binary.decode_unsigned(s) <= div(@group_order, 2)
    end
  end

  test "raw_to_der pads a high-bit r with a leading zero" do
    assert Secp256k1.raw_to_der(<<0xFF::256, 1::256>>) ==
             <<0x30, 0x07, 0x02, 0x02, 0x00, 0xFF, 0x02, 0x01, 0x01>>
  end

  test "raw_to_der and der_to_raw are inverses" do
    {_pub, priv} = Secp256k1.generate_keypair()
    raw = Secp256k1.sign(priv, "round trip")

    assert Secp256k1.der_to_raw(Secp256k1.raw_to_der(raw)) == raw
  end
end
