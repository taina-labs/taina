defmodule Ypy.Base32 do
  @moduledoc "Base32 do RFC 4648, minuscula, sem padding: a codificacao `b` do multibase."

  @alphabet ~c"abcdefghijklmnopqrstuvwxyz234567"

  @decode_map Map.new(Enum.with_index(@alphabet))

  @doc "Codifica um binario como base32 minuscula, sem padding."
  def encode(data) when is_binary(data) do
    Base.encode32(data, case: :lower, padding: false)
  end

  @doc """
  Decodifica base32 minuscula, sem padding. Levanta ArgumentError em caractere
  fora do alfabeto ou em bits de padding nao zero.
  """
  def decode!(str) when is_binary(str) do
    chars = String.to_charlist(str)
    bits = length(chars) * 5
    byte_len = div(bits, 8)
    pad_bits = bits - byte_len * 8

    bitstr =
      for c <- chars, into: <<>> do
        case @decode_map do
          %{^c => v} -> <<v::5>>
          _ -> raise ArgumentError, "invalid base32 character: #{<<c>>}"
        end
      end

    <<bin::binary-size(^byte_len), pad::size(^pad_bits)>> = bitstr

    if pad != 0 do
      raise ArgumentError, "non-zero base32 padding bits"
    end

    bin
  end
end
