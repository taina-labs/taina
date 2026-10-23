defmodule Ypy.Secp256k1 do
  @moduledoc """
  Utilitarios secp256k1: compressao de pontos, chaves publicas multibase e
  assinaturas ECDSA na forma exata que o ATProto espera (raw, low-S).
  """

  import Bitwise

  # varint do multicodec secp256k1-pub (0xE7)
  @multicodec_prefix <<0xE7, 0x01>>

  @group_order 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

  @doc "Gera {compressed_public_key, private_key}."
  def generate_keypair do
    {pub, priv} = :crypto.generate_key(:ecdh, :secp256k1)
    {compress(pub), priv}
  end

  @doc "Re-deriva a chave publica comprimida a partir de uma chave privada armazenada."
  def public_from_private(priv) do
    {pub, ^priv} = :crypto.generate_key(:ecdh, :secp256k1, priv)
    compress(pub)
  end

  @doc "Ponto nao comprimido (0x04 <> x <> y) para a forma comprimida SEC."
  def compress(<<4, x::binary-32, y::binary-32>>) do
    prefix = if rem(:binary.decode_unsigned(y), 2) == 0, do: 0x02, else: 0x03
    <<prefix, x::binary>>
  end

  @doc "Valor de `publicKeyMultibase` para uma chave secp256k1 comprimida."
  def public_key_multibase(compressed_pub) do
    "z" <> Ypy.Base58.encode(@multicodec_prefix <> compressed_pub)
  end

  @doc "ECDSA/SHA-256 sobre o payload, retornado como raw r || s com normalizacao low-S."
  def sign(priv, payload) do
    der = :crypto.sign(:ecdsa, :sha256, payload, [priv, :secp256k1])
    der_to_raw(der)
  end

  @doc "Sequencia DER para r || s fixo de 64 bytes, dobrando high-S em low-S."
  def der_to_raw(<<0x30, _len, 0x02, rlen, r::binary-size(rlen), 0x02, slen, s::binary-size(slen)>>) do
    r_int = :binary.decode_unsigned(r)

    s_int =
      case :binary.decode_unsigned(s) do
        s when s > div(@group_order, 2) -> @group_order - s
        s -> s
      end

    <<r_int::big-256, s_int::big-256>>
  end

  @doc "Inverso de der_to_raw/1, para quando for preciso verificar com :crypto."
  def raw_to_der(<<r::big-256, s::big-256>>) do
    rb = der_integer(r)
    sb = der_integer(s)
    body = <<0x02, byte_size(rb)>> <> rb <> <<0x02, byte_size(sb)>> <> sb
    <<0x30, byte_size(body)>> <> body
  end

  defp der_integer(int) do
    bin = :binary.encode_unsigned(int)

    case bin do
      <<b, _rest::binary>> when (b &&& 0x80) != 0 -> <<0>> <> bin
      _ -> bin
    end
  end
end
