defmodule Ypy.Tid do
  @moduledoc """
  Timestamp IDs: 13 caracteres de codificacao base32-sortable
  (timestamp_micros <<< 10 ||| clock_id). Puro: quem chama fornece o
  timestamp em microssegundos e o contador de clock id; nao ha leitura de
  relogio nem estado de processo. Duas chamadas com o mesmo `last` podem
  responder o mesmo valor, porque ambas receberam o mesmo timestamp. O
  aumento estrito vem de passar o inteiro que a chamada anterior retornou
  de volta como `last`, que e como as escritas da chain o usam.
  """

  import Bitwise

  @alphabet ~c"234567abcdefghijklmnopqrstuvwxyz"

  @doc """
  Retorna {tid_string, integer_value}, estritamente maior que `last`.

  `micros` e o timestamp em microssegundos e `clock_id` o contador de quem
  chama, nos 10 bits baixos.
  """
  def next(last, micros, clock_id)
      when is_integer(last) and last >= 0 and is_integer(micros) and micros >= 0 and is_integer(clock_id) and
             clock_id >= 0 and clock_id <= 1023 do
    n = max(last + 1, micros <<< 10 ||| clock_id)
    {encode(n), n}
  end

  @doc "Codifica um inteiro como a forma sortable de 13 caracteres. A codificacao so esta definida ate 64 bits."
  def encode(n) when is_integer(n) and n >= 0 do
    for i <- 0..12, into: "" do
      <<Enum.fetch!(@alphabet, n >>> (60 - i * 5) &&& 0x1F)>>
    end
  end
end
