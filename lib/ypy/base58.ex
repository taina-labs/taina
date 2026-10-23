defmodule Ypy.Base58 do
  @moduledoc "Codificacao base58btc (alfabeto Bitcoin), como usada pelo multibase `z`."

  @alphabet ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
  @decode_map Map.new(Enum.with_index(@alphabet))

  @doc "Codifica um binario como base58btc."
  def encode(bin) when is_binary(bin) do
    zeros = leading_zeros(bin, 0)
    chars = encode_int(:binary.decode_unsigned(bin), [])
    IO.iodata_to_binary([List.duplicate(?1, zeros), chars])
  end

  defp leading_zeros(<<0, rest::binary>>, acc), do: leading_zeros(rest, acc + 1)
  defp leading_zeros(_rest, acc), do: acc

  defp encode_int(0, acc), do: acc

  defp encode_int(n, acc) do
    encode_int(div(n, 58), [Enum.fetch!(@alphabet, rem(n, 58)) | acc])
  end

  @doc "Decodifica base58btc. Levanta ArgumentError em caractere fora do alfabeto."
  def decode!(str) when is_binary(str) do
    chars = String.to_charlist(str)
    {ones, rest} = Enum.split_while(chars, &(&1 == ?1))

    n = Enum.reduce(rest, 0, fn c, acc -> acc * 58 + index!(c) end)
    body = if n == 0, do: <<>>, else: :binary.encode_unsigned(n)

    IO.iodata_to_binary([List.duplicate(0, length(ones)), body])
  end

  defp index!(c) do
    case @decode_map do
      %{^c => i} -> i
      _ -> raise ArgumentError, "invalid base58 character: #{<<c>>}"
    end
  end
end
