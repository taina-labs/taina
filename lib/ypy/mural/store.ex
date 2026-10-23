defmodule Ypy.Mural.Store do
  @moduledoc """
  O append da cadeia unica (RFC_006 secao 8): le a cabeca, sela a entrada,
  assina pela `Ypy.KeyStore`, insere.

  O append acontece na mesma transacao da escrita do dado (`commit/6`): ou a
  entrada e o dado ficam juntos, ou nada fica. A serializacao e do banco
  (indice unico em `tekoa_id` + `seq`); o conflito de sequencia reexecuta a
  transacao inteira, ate tres tentativas, e ai responde
  `{:error, :chain_conflict}`. Nenhum processo por repo.
  """

  alias Ypy.Cbor
  alias Ypy.Cid
  alias Ypy.KeyStore
  alias Ypy.Mural
  alias Ypy.Mural.Entry
  alias Ypy.Mural.Queries

  @max_attempts 3

  @doc """
  Anexa `payload` (mapa de chaves de string) como entrada do `tipo` dado e
  devolve a linha inserida. O `tipo` entra no payload assinado e na coluna de
  projecao. Uma so tentativa: o conflito de sequencia em transacao e da
  transacao inteira recomecar, pelo `commit/6`.
  """
  @spec append(Ecto.Repo.t(), KeyStore.t(), integer(), String.t(), map()) ::
          {:ok, Entry.t()} | {:error, :chain_conflict | term()}
  def append(repo, keys, tekoa_id, tipo, payload) when is_binary(tipo) and is_map(payload) and is_integer(tekoa_id) do
    payload = Map.put(payload, "tipo", tipo)
    head = head(repo, tekoa_id)
    seq = next_seq(head)
    prev = prev_cid(head)
    body = %{"seq" => seq, "prev" => prev, "payload" => payload}

    with {:ok, signature} <- keys.__struct__.sign(keys, tekoa_id, Cbor.encode(body)) do
      insert_entry(repo, tekoa_id, tipo, payload, seq, prev, signature)
    end
  end

  defp next_seq(nil), do: 1
  defp next_seq(head), do: head.seq + 1

  defp prev_cid(nil), do: nil
  defp prev_cid(head), do: Cid.parse(head.cid)

  defp insert_entry(repo, tekoa_id, tipo, payload, seq, prev, signature) do
    entry = %{"seq" => seq, "prev" => prev, "payload" => payload, "signature" => signature}
    cid = Mural.entry_cid(entry)
    changeset = changeset(tekoa_id, seq, prev, tipo, payload, signature, cid)

    case repo.insert(changeset) do
      {:ok, row} ->
        {:ok, row}

      {:error, %Ecto.Changeset{errors: errors}} = error ->
        if conflict?(errors), do: {:error, :chain_conflict}, else: error
    end
  end

  @doc """
  Executa a escrita do dado e o append da cadeia na MESMA transacao
  (RFC_006 secao 8): ou a entrada fica com o dado, ou o dado volta. `data_fn`
  roda dentro da transacao e devolve `{:ok, valor}` ou `{:error, motivo}`;
  qualquer falha desfaz a transacao inteira. O conflito de sequencia em
  `(tekoa_id, seq)` reexecuta a transacao inteira (dado e cadeia), ate tres
  tentativas, e ai responde `{:error, :chain_conflict}`.
  """
  @spec commit(Ecto.Repo.t(), KeyStore.t(), integer(), String.t(), map(), (-> {:ok, term()}
                                                                              | {:error, term()})) ::
          {:ok, term()} | {:error, :chain_conflict | term()}
  def commit(repo, keys, tekoa_id, tipo, payload, data_fn) do
    commit(repo, keys, tekoa_id, tipo, payload, data_fn, @max_attempts)
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

  defp write(repo, keys, tekoa_id, tipo, payload, data_fn) do
    with {:ok, value} <- data_fn.(),
         {:ok, _entry} <- append(repo, keys, tekoa_id, tipo, payload) do
      value
    else
      {:error, reason} -> repo.rollback(reason)
    end
  end

  @doc "A cabeca da cadeia (nil no genesis)."
  def head(repo, tekoa_id), do: repo.one(Queries.head(tekoa_id))

  @doc "A cadeia inteira, do genesis em diante."
  def entradas(repo, tekoa_id), do: repo.all(Queries.entradas(tekoa_id))

  @doc "As entradas de um tipo (a projecao do mural)."
  def por_tipo(repo, tekoa_id, tipo), do: repo.all(Queries.por_tipo(tekoa_id, tipo))

  @doc "Insere pelo changeset dado (uso do produto e dos testes)."
  def insert(repo, changeset), do: repo.insert(changeset)

  defp conflict?(errors) do
    Enum.any?(errors, fn
      {_field, {_message, [constraint: :unique, constraint_name: _]}} -> true
      _ -> false
    end)
  end

  defp changeset(tekoa_id, seq, prev, tipo, payload, signature, cid) do
    Entry.changeset(%Entry{}, %{
      tekoa_id: tekoa_id,
      seq: seq,
      prev: prev && Cid.to_string(prev),
      tipo: tipo,
      payload: payload,
      signature: signature,
      cid: Cid.to_string(cid)
    })
  end
end
