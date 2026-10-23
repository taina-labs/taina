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
  conteudo.

  Puro: nenhuma funcao toca banco, relogio ou processo. Serializar escrita e
  do banco (indice unico em tekoa_id e seq, com retry no Store); aqui ficam
  so as respostas de exportacao e verificacao.
  """

  alias Ypy.Cbor
  alias Ypy.Cid
  alias Ypy.Mural.Entry
  alias Ypy.Mural.Queries
  alias Ypy.Secp256k1

  @typedoc "Uma entrada da cadeia: mapa de chaves de string com `seq` inteiro, `prev` como CID ou nil, `payload` de mapa e `signature` de 64 bytes."
  @type entry :: map()

  @doc """
  Sela a entrada `seq`: os bytes canonicos do corpo mais a assinatura da
  chave da Tekoa. `prev` e o CID da entrada anterior, ou nil na primeira.
  """
  @spec seal(pos_integer(), Cid.t() | nil, map(), binary()) :: entry()
  def seal(seq, prev, payload, priv) when is_integer(seq) and seq >= 1 and is_map(payload) do
    body = %{"seq" => seq, "prev" => prev, "payload" => payload}
    Map.put(body, "signature", Secp256k1.sign(priv, Cbor.encode(body)))
  end

  @doc "Os bytes DAG-CBOR canonicos da entrada completa, com a assinatura como byte string."
  @spec encode_entry(entry()) :: binary()
  def encode_entry(%{"seq" => _, "prev" => _, "payload" => payload, "signature" => signature} = entry)
      when is_map(payload) and is_binary(signature) do
    Cbor.encode(Map.put(entry, "signature", %Cbor.Bytes{data: signature}))
  end

  @doc "O CIDv1 da entrada completa: o endereco pelo qual ela e alcancavel."
  @spec entry_cid(entry()) :: Cid.t()
  def entry_cid(entry), do: Cid.from_data(encode_entry(entry))

  @doc "Verifica a assinatura de uma entrada contra a chave publica da Tekoa."
  @spec verify_entry(binary(), entry()) :: :ok | {:error, :bad_entry | :bad_signature}
  def verify_entry(pub, entry) do
    case body(entry) do
      :error -> {:error, :bad_entry}
      bytes -> check_signature(pub, bytes, entry)
    end
  end

  @doc """
  Verifica a cadeia inteira, do genesis ate a ultima entrada.

  O primeiro item comeca em seq 1 e sem prev; cada entrada seguinte tem seq
  imediatamente maior e prev igual ao CID da entrada anterior, e a assinatura
  de todas confere com a chave publica da Tekoa. Devolve :ok, ou
  {:error, {indice, motivo}} com o indice na lista, a partir de 0, onde a
  cadeia quebra, e motivo em :bad_seq, :bad_link, :bad_entry ou
  :bad_signature.
  """
  @spec verify_chain(binary(), [entry()]) :: :ok | {:error, {non_neg_integer(), atom()}}
  def verify_chain(pub, entries) when is_binary(pub) and is_list(entries), do: verify_chain(pub, entries, 0, 1, nil)

  defp verify_chain(_pub, [], _index, _expected_seq, _expected_prev), do: :ok

  defp verify_chain(pub, [entry | rest], index, expected_seq, expected_prev) do
    with :ok <- check_link(entry, expected_seq, expected_prev),
         :ok <- verify_entry(pub, entry) do
      verify_chain(pub, rest, index + 1, expected_seq + 1, entry_cid(entry))
    else
      {:error, reason} -> {:error, {index, reason}}
    end
  end

  # O que a assinatura cobre: o corpo sem a assinatura, nos mesmos tres
  ## A projecao social

  # campos que o seal canonicou. Um campo estranho na entrada nao entra na
  # assinatura, e os tres precisam estar la com os tipos certos.
  # A partir daqui a cadeia e lida do banco, com o repo sempre como primeiro
  # argumento (RFC_006 D4). A matematica acima continua pura: verificar uma
  # cadeia exportada nunca precisa de repo.
  defp body(%{"seq" => seq, "prev" => prev, "payload" => payload}) when is_integer(seq) and is_map(payload),
    do: Cbor.encode(%{"seq" => seq, "prev" => prev, "payload" => payload})

  defp body(_), do: :error

  defp check_signature(pub, bytes, %{"signature" => sig}) when is_binary(sig) and byte_size(sig) == 64 do
    if :crypto.verify(:ecdsa, :sha256, bytes, Secp256k1.raw_to_der(sig), [pub, :secp256k1]),
      do: :ok,
      else: {:error, :bad_signature}
  end

  defp check_signature(_pub, _bytes, _entry), do: {:error, :bad_entry}

  defp check_link(%{"seq" => seq, "prev" => prev}, expected_seq, expected_prev) do
    cond do
      seq != expected_seq -> {:error, :bad_seq}
      prev != expected_prev -> {:error, :bad_link}
      true -> :ok
    end
  end

  defp check_link(_entry, _expected_seq, _expected_prev), do: {:error, :bad_entry}

  @doc """
  O mural legivel: a projecao da cadeia, com filtro por tipo de entrada,
  ordem da mais recente para a mais antiga e paginacao por cursor de `seq`.
  Opcoes: `:tipo`, `:limit` (padrao 50), `:cursor` (seq do ultimo item).
  """
  @spec entradas(Ecto.Repo.t(), integer(), keyword()) :: [Entry.t()]
  def entradas(repo, tekoa_id, opts \\ []) do
    import Ecto.Query

    query =
      if tipo = opts[:tipo] do
        Queries.por_tipo(tekoa_id, tipo)
      else
        Queries.entradas(tekoa_id)
      end

    query =
      if cursor = opts[:cursor] do
        where(query, [e], e.seq < ^cursor)
      else
        query
      end

    repo.all(limit(query, ^(opts[:limit] || 50)))
  end

  @doc "Uma entrada pelo seq, dentro da Tekoa."
  @spec entrada(Ecto.Repo.t(), integer(), pos_integer()) :: Entry.t() | nil
  def entrada(repo, tekoa_id, seq), do: repo.one(Queries.por_seq(tekoa_id, seq))

  @doc """
  Verifica a cadeia inteira da Tekoa contra a chave publica ativa dela, do
  genesis a cabeca. Devolve :ok, {:error, {indice, motivo}} na entrada que
  quebra, ou {:error, :not_found} quando a Tekoa nao tem chave ativa.
  """
  @spec verificar_cadeia(Ecto.Repo.t(), integer()) ::
          :ok | {:error, {non_neg_integer(), atom()}} | {:error, :not_found}
  def verificar_cadeia(repo, tekoa_id) do
    case Ypy.Maraca.Store.chave_ativa(repo, tekoa_id) do
      %Ypy.Maraca.TekoaKey{pub: pub} ->
        entries =
          repo
          |> Ypy.Mural.Store.entradas(tekoa_id)
          |> Enum.map(&reconstruct/1)

        verify_chain(pub, entries)

      nil ->
        {:error, :not_found}
    end
  end

  # A linha de volta ao mapa do fio CBOR: prev volta a ser link e a
  # assinatura volta a ser byte string; a matematica pura confere o resto.
  defp reconstruct(%Entry{} = row) do
    %{
      "seq" => row.seq,
      "prev" => row.prev && Cid.parse(row.prev),
      "payload" => row.payload,
      "signature" => row.signature
    }
  end
end
