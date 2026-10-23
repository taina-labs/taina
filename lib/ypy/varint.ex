defmodule Ypy.Varint do
  @moduledoc "Varints LEB128 sem sinal, como usados por multihash, CID e CAR."

  import Bitwise

  @doc "Codifica um inteiro sem sinal. Levanta FunctionClauseError em um negativo."
  def encode(n) when is_integer(n) and n >= 0, do: encode(n, [])

  defp encode(n, acc) when n < 0x80, do: IO.iodata_to_binary(Enum.reverse([n | acc]))

  defp encode(n, acc) do
    byte = (n &&& 0x7F) ||| 0x80
    encode(n >>> 7, [byte | acc])
  end

  @doc "Retorna {value, rest}."
  def decode(bin), do: decode(bin, 0, 0)

  defp decode(<<>>, _acc, _shift), do: raise(ArgumentError, "truncated varint")
  defp decode(_bin, _acc, shift) when shift > 64, do: raise(ArgumentError, "varint too long")

  defp decode(<<b, rest::binary>>, acc, shift) do
    n = acc ||| (b &&& 0x7F) <<< shift
    if b < 0x80, do: {n, rest}, else: decode(rest, n, shift + 7)
  end
end
