defmodule Ypy.Cbor do
  @moduledoc """
  DAG-CBOR deterministico.

  Mapeamento do modelo de dados:
    nil / true / false        -> valores simples
    integer                   -> major types 0/1 (apenas faixa uint64)
    float                     -> float de 64 bits (0xFB)
    binary (UTF-8 valido)     -> text string
    %Ypy.Cbor.Bytes{}         -> byte string
    list                      -> array
    map (chaves binarias)     -> map, chaves ordenadas por tamanho e depois bytewise
    %Ypy.Cid{}                -> link da tag 42
  """

  alias Ypy.Cbor.Bytes
  alias Ypy.Cid

  @doc "Codifica um termo como DAG-CBOR. Levanta ArgumentError em qualquer coisa que o modelo de dados nao cubra."
  def encode(term), do: IO.iodata_to_binary(enc(term))

  defp enc(nil), do: <<0xF6>>
  defp enc(false), do: <<0xF4>>
  defp enc(true), do: <<0xF5>>

  defp enc(%Cid{} = cid) do
    payload = Cid.to_bytes(cid)
    [head(6, 42), head(2, byte_size(payload) + 1), 0, payload]
  end

  defp enc(%Bytes{data: data}) when is_binary(data) do
    [head(2, byte_size(data)), data]
  end

  defp enc(int) when is_integer(int) and int >= 0, do: head(0, int)
  defp enc(int) when is_integer(int) and int < 0, do: head(1, -1 - int)

  defp enc(float) when is_float(float), do: <<0xFB, float::float-64>>

  defp enc(bin) when is_binary(bin) do
    if !String.valid?(bin), do: raise(ArgumentError, "text strings must be valid UTF-8")
    [head(3, byte_size(bin)), bin]
  end

  defp enc(list) when is_list(list) do
    [head(4, length(list)) | Enum.map(list, &enc/1)]
  end

  defp enc(map) when is_map(map) do
    entries =
      map
      |> Map.to_list()
      |> Enum.map(fn
        {k, v} when is_binary(k) -> {k, v}
        {k, _v} -> raise ArgumentError, "map keys must be strings, got: #{inspect(k)}"
      end)
      |> Enum.sort_by(fn {k, _v} -> {byte_size(k), k} end)

    [head(5, length(entries)) | Enum.map(entries, fn {k, v} -> [enc(k), enc(v)] end)]
  end

  defp enc(other), do: raise(ArgumentError, "not encodable as DAG-CBOR: #{inspect(other)}")

  # Forma mais curta do argumento (o "head" de cada item).
  defp head(mt, n) when n >= 0 and n < 24, do: <<mt::3, n::5>>
  defp head(mt, n) when n < 0x100, do: <<mt::3, 24::5, n::8>>
  defp head(mt, n) when n < 0x1_0000, do: <<mt::3, 25::5, n::16>>
  defp head(mt, n) when n < 0x1_0000_0000, do: <<mt::3, 26::5, n::32>>
  defp head(mt, n) when n < 0x1_0000_0000_0000_0000, do: <<mt::3, 27::5, n::64>>
  defp head(_mt, n), do: raise(ArgumentError, "out of uint64 range: #{n}")

  @doc "Decodifica um item. Retorna {term, rest}."
  def decode(bin), do: dec(bin)

  @doc "Decodifica exatamente um item e exige que a entrada seja consumida por completo."
  def decode!(bin) do
    {term, ""} = dec(bin)
    term
  end

  defp dec(<<7::3, 20::5, rest::binary>>), do: {false, rest}
  defp dec(<<7::3, 21::5, rest::binary>>), do: {true, rest}
  defp dec(<<7::3, 22::5, rest::binary>>), do: {nil, rest}
  defp dec(<<7::3, 26::5, f::float-32, rest::binary>>), do: {f, rest}
  defp dec(<<7::3, 27::5, f::float-64, rest::binary>>), do: {f, rest}

  defp dec(<<7::3, 25::5, _rest::binary>>) do
    raise ArgumentError, "16-bit floats are not valid DAG-CBOR"
  end

  defp dec(<<mt::3, ai::5, rest::binary>>) when mt in 0..6 do
    {n, rest} = arg(ai, rest)
    dec_type(mt, n, rest)
  end

  defp dec_type(0, n, rest), do: {n, rest}
  defp dec_type(1, n, rest), do: {-1 - n, rest}

  defp dec_type(2, n, rest) do
    <<data::binary-size(^n), tail::binary>> = rest
    {%Bytes{data: data}, tail}
  end

  defp dec_type(3, n, rest) do
    <<data::binary-size(^n), tail::binary>> = rest

    if !String.valid?(data) do
      raise ArgumentError, "invalid UTF-8 in text string"
    end

    {data, tail}
  end

  defp dec_type(4, n, rest), do: dec_list(n, rest, [])
  defp dec_type(5, n, rest), do: dec_map(n, rest, %{})

  defp dec_type(6, n, rest) do
    if n != 42, do: raise(ArgumentError, "unsupported tag: #{n}")

    case dec(rest) do
      {%Bytes{data: <<0, cid_bytes::binary>>}, tail} -> {Cid.from_bytes(cid_bytes), tail}
      _ -> raise ArgumentError, "malformed CID link in tag 42"
    end
  end

  defp dec_list(0, rest, acc), do: {Enum.reverse(acc), rest}

  defp dec_list(n, bin, acc) do
    {term, rest} = dec(bin)
    dec_list(n - 1, rest, [term | acc])
  end

  defp dec_map(0, rest, acc), do: {acc, rest}

  defp dec_map(n, bin, acc) do
    {key, rest} = dec(bin)

    if !is_binary(key) do
      raise ArgumentError, "map keys must be strings"
    end

    {value, rest} = dec(rest)
    dec_map(n - 1, rest, Map.put(acc, key, value))
  end

  defp arg(ai, rest) when ai < 24, do: {ai, rest}
  defp arg(24, <<n::8, rest::binary>>), do: {n, rest}
  defp arg(25, <<n::16, rest::binary>>), do: {n, rest}
  defp arg(26, <<n::32, rest::binary>>), do: {n, rest}
  defp arg(27, <<n::64, rest::binary>>), do: {n, rest}

  defp arg(31, _rest), do: raise(ArgumentError, "indefinite-length items are not valid DAG-CBOR")
  defp arg(ai, _rest), do: raise(ArgumentError, "reserved additional info: #{ai}")
end
