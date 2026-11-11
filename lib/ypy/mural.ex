defmodule Ypy.Mural do
  @moduledoc """
  A matematica da cadeia unica por Tekoa (RFC_006 secao 8): selar, verificar
  e encadear entradas.

  O mural e os commits de record sao uma so cadeia: cada entrada leva `seq`,
  `prev` (o CID da entrada anterior completa), `payload` e a assinatura da
  chave da Tekoa. Ato social (convite, publicar-na-praca, concessao) e put de
  arquivo sao entradas da mesma cadeia, e o mural legivel e uma projecao
  dela.

  A entrada e um mapa de chaves de string, na forma que o CBOR fala: `"seq"`
  inteiro, `"prev"` como link CID (o primeiro, genesis, leva nil), `"payload"`
  como o dado do ato e `"signature"` como os 64 bytes r || s da assinatura.
  O que e assinado sao os bytes DAG-CBOR canonicos do corpo (sem a
  assinatura); `prev` aponta para o CID da entrada anterior completa, com
  assinatura incluida, para a ordem das entradas ficar selada junto com o
  conteudo. New entries also carry `"signing_key"` to identify their public
  key across rotations. Legacy entries without it remain supported.

  Toda a matematica da cadeia e pura: selar entradas, calcular CIDs e conferir
  a ordem, os links e as assinaturas.
  """

  alias Ypy.Cbor
  alias Ypy.Cbor.Bytes
  alias Ypy.Cid
  alias Ypy.Secp256k1

  @signature_field "signature"
  @signing_key_field "signing_key"

  @type binary_data :: binary()
  @type cid :: Cid.t()
  @typedoc "Uma entrada da cadeia: mapa de chaves de string com `seq` inteiro, `prev` como CID ou nil, `payload` de mapa e `signature` de 64 bytes."
  @type entry :: map()
  @type params :: map()
  @type status :: atom()

  @doc "Os bytes DAG-CBOR canonicos da entrada completa, com a assinatura como byte string."
  @spec encode_entry(entry()) :: binary_data()
  def encode_entry(%{"seq" => _, "prev" => _, "payload" => _, @signature_field => signature} = entry)
      when is_binary(signature) do
    entry = Map.put(entry, @signature_field, %Bytes{data: signature})

    entry =
      case Map.get(entry, @signing_key_field) do
        key when is_binary(key) -> Map.put(entry, @signing_key_field, %Bytes{data: key})
        _ -> entry
      end

    Cbor.encode(entry)
  end

  @doc "O CIDv1 da entrada completa: o endereco pelo qual ela e alcancavel."
  @spec entry_cid(entry()) :: cid()
  def entry_cid(entry), do: Cid.from_data(encode_entry(entry))

  @doc """
  Sela a entrada `seq`: os bytes canonicos do corpo mais a assinatura da
  chave da Tekoa. `prev` e o CID da entrada anterior, ou nil na primeira.
  """
  @spec seal(pos_integer(), cid() | nil, params(), binary_data()) :: entry()
  def seal(seq, prev, %{} = payload, priv) when is_integer(seq) and seq >= 1 do
    body = %{"seq" => seq, "prev" => prev, "payload" => payload}
    Map.put(body, @signature_field, Secp256k1.sign(priv, Cbor.encode(body)))
  end

  @doc "Seals an entry with an explicitly identified signing key."
  @spec seal(pos_integer(), cid() | nil, params(), binary_data(), binary_data()) :: entry()
  def seal(seq, prev, %{} = payload, priv, signing_key) when is_integer(seq) and seq >= 1 and is_binary(signing_key) do
    body = %{"seq" => seq, "prev" => prev, "payload" => payload, @signing_key_field => signing_key}
    # The function head guarantees the exact body shape accepted by signing_bytes/1.
    # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingErrorHandling
    {:ok, bytes} = signing_bytes(body)
    Map.put(body, @signature_field, Secp256k1.sign(priv, bytes))
  end

  @doc "Returns the canonical bytes signed for an entry body."
  @spec signing_bytes(entry()) :: {:ok, binary_data()} | :error
  def signing_bytes(%{"seq" => seq, "prev" => prev, "payload" => %{} = payload} = entry) when is_integer(seq) do
    body = %{"seq" => seq, "prev" => prev, "payload" => payload}

    case Map.get(entry, @signing_key_field) do
      nil ->
        {:ok, Cbor.encode(body)}

      pub when is_binary(pub) ->
        {:ok, Cbor.encode(Map.put(body, @signing_key_field, %Bytes{data: pub}))}

      _ ->
        :error
    end
  end

  def signing_bytes(_entry), do: :error

  @doc """
  Verifica a cadeia inteira, do genesis ate a ultima entrada. Uma lista de
  chaves publicas permite verificar segmentos assinados antes e depois de
  rotacoes. Entradas antigas sem identificador sao conferidas contra todas.

  O primeiro item comeca em seq 1 e sem prev; cada entrada seguinte tem seq
  imediatamente maior e prev igual ao CID da entrada anterior, e cada
  assinatura confere com a chave publica identificada. Devolve :ok, ou
  {:error, {indice, motivo}} com o indice na lista, a partir de 0, onde a
  cadeia quebra, e motivo em :bad_seq, :bad_link, :bad_entry ou
  :bad_signature.
  """
  @spec verify_chain(binary_data() | [binary_data()], [entry()]) :: :ok | {:error, {non_neg_integer(), status()}}
  def verify_chain(pub, entries) when is_binary(pub), do: verify_chain([pub], entries)

  def verify_chain(public_keys, entries) when is_list(public_keys) and is_list(entries) do
    verify_chain_entries(public_keys, entries, 0, 1, nil)
  end

  @doc "Verifica a assinatura de uma entrada contra a chave publica da Tekoa."
  @spec verify_entry(binary_data(), entry()) :: :ok | {:error, :bad_entry | :bad_signature}
  def verify_entry(pub, entry) do
    case signing_bytes(entry) do
      {:ok, bytes} -> check_signature(pub, bytes, entry)
      :error -> {:error, :bad_entry}
    end
  end

  defp check_link(%{"seq" => seq, "prev" => prev}, expected_seq, expected_prev) do
    cond do
      seq != expected_seq -> {:error, :bad_seq}
      prev != expected_prev -> {:error, :bad_link}
      true -> :ok
    end
  end

  defp check_link(_entry, _expected_seq, _expected_prev), do: {:error, :bad_entry}

  defp check_signature(pub, bytes, %{@signature_field => sig}) when is_binary(sig) and byte_size(sig) == 64 do
    if :crypto.verify(:ecdsa, :sha256, bytes, Secp256k1.raw_to_der(sig), [pub, :secp256k1]),
      do: :ok,
      else: {:error, :bad_signature}
  end

  defp check_signature(_pub, _bytes, _entry), do: {:error, :bad_entry}

  defp verify_chain_entries(_public_keys, [], _index, _expected_seq, _expected_prev), do: :ok

  defp verify_chain_entries(public_keys, [entry | rest], index, expected_seq, expected_prev) do
    with :ok <- check_link(entry, expected_seq, expected_prev),
         :ok <- verify_entry_with_keys(public_keys, entry) do
      verify_chain_entries(public_keys, rest, index + 1, expected_seq + 1, entry_cid(entry))
    else
      {:error, reason} -> {:error, {index, reason}}
    end
  end

  defp verify_entry_with_keys(public_keys, entry) do
    case Map.get(entry, @signing_key_field) do
      nil ->
        verify_legacy_entry(public_keys, entry)

      pub when is_binary(pub) ->
        if pub in public_keys, do: verify_entry(pub, entry), else: {:error, :bad_signature}

      _ ->
        {:error, :bad_entry}
    end
  end

  defp verify_legacy_entry(public_keys, entry) do
    Enum.reduce_while(public_keys, {:error, :bad_signature}, fn pub, _result ->
      case verify_entry(pub, entry) do
        :ok -> {:halt, :ok}
        {:error, :bad_entry} = error -> {:halt, error}
        {:error, :bad_signature} -> {:cont, {:error, :bad_signature}}
      end
    end)
  end
end
