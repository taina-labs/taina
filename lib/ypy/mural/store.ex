defmodule Ypy.Mural.Store do
  @moduledoc """
  O append da cadeia unica (RFC_006 secao 8): le a cabeca, sela a entrada,
  assina pela `Ypy.KeyStore`, insere. A leitura mora aqui junto, com o repo
  sempre como primeiro argumento (RFC_006 D4): a cadeia inteira (`cadeia/2`),
  a projecao legivel (`entradas/3`) e a verificacao contra a chave ativa
  (`verificar_cadeia/2`). A matematica de selar e conferir e do `Ypy.Mural`,
  puro.

  O append acontece na mesma transacao da escrita do dado (`commit/6`): ou a
  entrada e o dado ficam juntos, ou nada fica. A serializacao e do banco
  (indice unico em `tekoa_id` + `seq`); o conflito de sequencia reexecuta a
  transacao inteira, ate tres tentativas, e ai responde
  `{:error, :chain_conflict}`. Nenhum processo por repo.
  """

  import Ecto.Query, only: [exclude: 2, limit: 2, order_by: 3]

  alias Ypy.Cid
  alias Ypy.KeyStore
  alias Ypy.Maraca.Store, as: MaracaStore
  alias Ypy.Maraca.TekoaKey
  alias Ypy.Mural
  alias Ypy.Mural.Entry
  alias Ypy.Mural.Queries

  @max_attempts 3

  @type changeset :: Ecto.Changeset.t()
  @type entry :: Entry.t()
  @type keystore :: KeyStore.t()
  @type opts :: keyword()
  @type params :: map()
  @type repo :: Ecto.Repo.t()
  @type status :: atom()
  @type tekoa_id :: integer()
  @type text :: String.t()

  @doc """
  Anexa `payload` (mapa de chaves de string) como entrada do `tipo` dado e
  devolve a linha inserida. O `tipo` entra no payload assinado e na coluna de
  projecao. Uma so tentativa: o conflito de sequencia em transacao e da
  transacao inteira recomecar, pelo `commit/6`.
  """
  @spec append(repo(), keystore(), tekoa_id(), text(), params()) :: {:ok, entry()} | {:error, :chain_conflict | term()}
  def append(repo, keys, tekoa_id, tipo, %{} = payload) when is_binary(tipo) and is_integer(tekoa_id) do
    payload = Map.put(payload, "tipo", tipo)
    head = head(repo, tekoa_id)
    seq = next_seq(head)
    prev = prev_cid(head)
    body = %{"seq" => seq, "prev" => prev, "payload" => payload}

    with %TekoaKey{pub: pub} <- MaracaStore.chave_ativa(repo, tekoa_id),
         signing_body = Map.put(body, "signing_key", pub),
         {:ok, signed_bytes} <- Mural.signing_bytes(signing_body),
         {:ok, signature} <- keys.__struct__.sign(keys, tekoa_id, signed_bytes),
         :ok <- Mural.verify_entry(pub, Map.put(signing_body, "signature", signature)) do
      insert_entry(repo, tekoa_id, tipo, payload, seq, prev, signature, pub)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "A cadeia inteira, do genesis em diante."
  def cadeia(repo, tekoa_id), do: repo.all(Queries.entradas(tekoa_id))

  @doc """
  Executa a escrita do dado e o append da cadeia na MESMA transacao
  (RFC_006 secao 8): ou a entrada fica com o dado, ou o dado volta. `data_fn`
  roda dentro da transacao e devolve `{:ok, valor}` ou `{:error, motivo}`;
  qualquer falha desfaz a transacao inteira. O conflito de sequencia em
  `(tekoa_id, seq)` reexecuta a transacao inteira (dado e cadeia), ate tres
  tentativas, e ai responde `{:error, :chain_conflict}`.
  """
  @spec commit(repo(), keystore(), tekoa_id(), text(), params(), (-> {:ok, term()}
                                                                     | {:error, term()})) ::
          {:ok, term()} | {:error, :chain_conflict | term()}
  def commit(repo, keys, tekoa_id, tipo, payload, data_fn) do
    commit(repo, keys, tekoa_id, tipo, payload, data_fn, @max_attempts)
  end

  defp changeset(tekoa_id, seq, prev, tipo, payload, signature, signing_key, cid) do
    Entry.changeset(%Entry{}, %{
      tekoa_id: tekoa_id,
      seq: seq,
      prev: prev && Cid.to_string(prev),
      tipo: tipo,
      payload: payload,
      signature: signature,
      signing_key: signing_key,
      cid: Cid.to_string(cid)
    })
  end

  defp commit(repo, keys, tekoa_id, tipo, payload, data_fn, attempts) do
    result = repo.transaction(fn -> write(repo, keys, tekoa_id, tipo, payload, data_fn) end)

    case result do
      {:ok, value} ->
        {:ok, value}

      {:error, :chain_conflict} when attempts > 1 ->
        commit(repo, keys, tekoa_id, tipo, payload, data_fn, attempts - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_entry(repo, tekoa_id, tipo, payload, seq, prev, signature, signing_key) do
    entry = %{
      "seq" => seq,
      "prev" => prev,
      "payload" => payload,
      "signature" => signature,
      "signing_key" => signing_key
    }

    cid = Mural.entry_cid(entry)
    changeset = changeset(tekoa_id, seq, prev, tipo, payload, signature, signing_key, cid)

    case repo.insert(changeset) do
      {:ok, row} ->
        {:ok, row}

      {:error, %Ecto.Changeset{} = cs} = error ->
        if unique_conflict?(cs), do: {:error, :chain_conflict}, else: error
    end
  end

  defp next_seq(nil), do: 1
  defp next_seq(head), do: head.seq + 1

  defp prev_cid(nil), do: nil
  defp prev_cid(head), do: Cid.parse(head.cid)

  # A linha de volta ao mapa do fio CBOR: prev volta a ser link e a
  # assinatura volta a ser byte string; a matematica pura confere o resto.
  defp reconstruct(%Entry{} = row) do
    entry = %{
      "seq" => row.seq,
      "prev" => row.prev && Cid.parse(row.prev),
      "payload" => row.payload,
      "signature" => row.signature
    }

    if is_binary(row.signing_key), do: Map.put(entry, "signing_key", row.signing_key), else: entry
  end

  defp write(repo, keys, tekoa_id, tipo, payload, data_fn) do
    with {:ok, value} <- data_fn.(),
         {:ok, _entry} <- append(repo, keys, tekoa_id, tipo, payload) do
      value
    else
      {:error, reason} -> repo.rollback(reason)
    end
  end

  @doc "Uma entrada pelo seq, dentro da Tekoa."
  @spec entrada(repo(), tekoa_id(), pos_integer()) :: entry() | nil
  def entrada(repo, tekoa_id, seq), do: repo.one(Queries.por_seq(tekoa_id, seq))

  @doc """
  O mural legivel: a projecao da cadeia, da entrada mais recente para a mais
  antiga, com filtro por tipo e paginacao por cursor de `seq`. Opcoes:
  `:tipo`, `:limit` (padrao 50), `:cursor` (seq do ultimo item).
  """
  @spec entradas(repo(), tekoa_id(), opts()) :: [entry()]
  def entradas(repo, tekoa_id, opts \\ []) do
    query =
      if tipo = Keyword.get(opts, :tipo) do
        Queries.por_tipo(tekoa_id, tipo)
      else
        Queries.entradas(tekoa_id)
      end

    query =
      if cursor = Keyword.get(opts, :cursor) do
        Queries.antes(query, cursor)
      else
        query
      end

    query =
      query
      |> exclude(:order_by)
      |> order_by([e], desc: e.seq)
      |> limit(^(Keyword.get(opts, :limit) || 50))

    repo.all(query)
  end

  @doc "A cabeca da cadeia (nil no genesis)."
  def head(repo, tekoa_id), do: repo.one(Queries.head(tekoa_id))

  @doc "Se o erro e de indice unico: aceita o changeset ou a lista de erros dele."
  @spec unique_conflict?(changeset() | [term()]) :: boolean()
  def unique_conflict?(%Ecto.Changeset{errors: errors}), do: unique_conflict?(errors)

  def unique_conflict?(errors) when is_list(errors) do
    Enum.any?(errors, fn
      {_field, {_message, [constraint: :unique, constraint_name: _]}} -> true
      _ -> false
    end)
  end

  @doc """
  Verifica a cadeia inteira da Tekoa contra as chaves publicas ativas e
  aposentadas, do genesis a cabeca. Entradas antigas sem identificador sao
  tentadas contra cada chave registrada. Devolve :ok,
  {:error, {indice, motivo}} na entrada que quebra, ou {:error, :not_found}
  quando a Tekoa nao tem chave ativa.
  """
  @spec verificar_cadeia(repo(), tekoa_id()) :: :ok | {:error, {non_neg_integer(), status()}} | {:error, :not_found}
  def verificar_cadeia(repo, tekoa_id) do
    keys = MaracaStore.chaves(repo, tekoa_id)

    if Enum.any?(keys, &is_nil(&1.aposentada_em)) do
      entries =
        repo
        |> cadeia(tekoa_id)
        |> Enum.map(&reconstruct/1)

      Mural.verify_chain(Enum.map(keys, & &1.pub), entries)
    else
      {:error, :not_found}
    end
  end
end
