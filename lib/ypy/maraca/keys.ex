defmodule Ypy.Maraca.Keys do
  @moduledoc """
  Chaves da Tekoa: par secp256k1, chave publica em multibase Multikey,
  verificacao pura e fingerprint.

  A geracao recebe a entropia como argumento (o nucleo nao sorteia nada por
  conta propria); quem guarda a chave privada e o `Ypy.KeyStore` do produto.
  A verificacao, ao contrario, nunca passa por behaviour: verificar uma cadeia
  exportada ou recebida em federacao e codigo do nucleo, feito com o dado de
  chave publica em maos (RFC_006, secao 5).
  """

  alias Ypy.Base32
  alias Ypy.Secp256k1

  @group_order 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141
  @pub_size 33
  @sig_size 64
  @fingerprint_bytes 10

  @typedoc "Chave publica comprimida e chave privada, cada uma com 32/33 bytes."
  @type keypair :: {pub :: binary(), priv :: binary()}

  @doc """
  Gera o par a partir da entropia privada: 32 bytes com valor entre 1 e a
  ordem da curva. Levanta ArgumentError em entropia invalida.
  """
  def generate(entropy) when is_binary(entropy) and byte_size(entropy) == 32 do
    d = :binary.decode_unsigned(entropy)

    if d == 0 or d >= @group_order do
      raise ArgumentError, "invalid entropy: expected 32 bytes with 1 <= value < curve order"
    end

    {Secp256k1.public_from_private(entropy), entropy}
  end

  @doc "`publicKeyMultibase` (Multikey, prefixo `z`) da chave publica comprimida."
  def public_key_multibase(pub) when byte_size(pub) == @pub_size do
    Secp256k1.public_key_multibase(pub)
  end

  @doc """
  Verifica uma assinatura raw de 64 bytes (`r || s`, low-S) sobre o payload,
  com a chave publica comprimida. Ponto publico malformado devolve false:
  o dado vem da cadeia e pode ser adulterado.
  """
  def verify(pub, sig, payload) when byte_size(pub) == @pub_size and byte_size(sig) == @sig_size and is_binary(payload) do
    der = Secp256k1.raw_to_der(sig)
    :crypto.verify(:ecdsa, :sha256, payload, der, [pub, :secp256k1])
  rescue
    ErlangError -> false
  end

  @doc """
  Impressao digital deterministica da chave publica: 16 caracteres base32 dos
  primeiros 80 bits do SHA-256 da chave comprimida. Para conferencia humana
  (rotacao de chave, logs), nao como identificador.
  """
  def fingerprint(pub) when byte_size(pub) == @pub_size do
    <<fingerprint::binary-size(@fingerprint_bytes), _rest::binary>> = :crypto.hash(:sha256, pub)
    Base32.encode(fingerprint)
  end
end
