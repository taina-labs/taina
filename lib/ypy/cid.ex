defmodule Ypy.Cid do
  @moduledoc "CIDv1: versao, codec e um multihash sha2-256."

  alias Ypy.Base32
  alias Ypy.Varint

  @sha2_256 0x12
  @dag_cbor 0x71
  @raw 0x55

  defstruct version: 1, codec: @dag_cbor, hash_algo: @sha2_256, digest: nil

  @typedoc "Um CIDv1: versao, codec, algoritmo do multihash e digest."
  @type t :: %__MODULE__{
          version: pos_integer(),
          codec: non_neg_integer(),
          hash_algo: non_neg_integer(),
          digest: binary() | nil
        }

  @doc "Codec para bytes brutos enderecados por conteudo."
  def raw, do: @raw

  @doc "Codigo multihash para sha2-256."
  def sha2_256, do: @sha2_256

  @doc "Constroi um CIDv1 para `data` sob o codec dado (padrao dag-cbor)."
  def from_data(data, codec \\ @dag_cbor) do
    %__MODULE__{codec: codec, digest: :crypto.hash(:sha256, data)}
  end

  @doc "Constroi um CIDv1 de um digest sha2-256 ja calculado, sob o codec dado (padrao raw)."
  def from_digest(digest, codec \\ @raw) do
    %__MODULE__{codec: codec, digest: digest}
  end

  @doc "Serializa para versao, codec e bytes de multihash."
  def to_bytes(%__MODULE__{} = cid) do
    Varint.encode(cid.version) <>
      Varint.encode(cid.codec) <>
      Varint.encode(cid.hash_algo) <>
      Varint.encode(byte_size(cid.digest)) <>
      cid.digest
  end

  @doc "Renderiza a forma string do multibase: prefixo b sobre base32 minuscula."
  def to_string(cid), do: "b" <> Base32.encode(to_bytes(cid))

  @doc "Parseia uma string CID multibase base32. Levanta erro em entrada malformada."
  def parse("b" <> rest), do: rest |> Base32.decode!() |> from_bytes()
  def parse(_), do: raise(ArgumentError, "not a multibase base32 CID")

  @doc """
  Parseia uma string CID, ou responde :error.

  Levantar erro e o certo para um CID que o proprio kernel calculou e o
  errado para um que chega de entrada nao confiavel: o raise acontece dentro
  de quem trata a entrada, entao uma string malformada derruba esse
  tratamento junto. Todo caminho que le um CID do fio passa por aqui, nao
  por parse/1.
  """
  def safe_parse(cid) do
    {:ok, parse(cid)}
  rescue
    ArgumentError -> :error
  end

  @doc "Parseia a forma binaria. Levanta ArgumentError em versao diferente de 1 ou cauda malformada."
  def from_bytes(bin) do
    {version, rest} = Varint.decode(bin)

    if version != 1 do
      raise ArgumentError, "unsupported CID version: #{version}"
    end

    {codec, rest} = Varint.decode(rest)
    {algo, rest} = Varint.decode(rest)
    {len, rest} = Varint.decode(rest)

    case rest do
      <<digest::binary-size(^len)>> ->
        %__MODULE__{codec: codec, hash_algo: algo, digest: digest}

      _ ->
        raise ArgumentError, "malformed CID bytes: truncated digest or trailing garbage"
    end
  end
end
