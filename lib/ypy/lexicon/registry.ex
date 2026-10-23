defmodule Ypy.Lexicon.Registry do
  @moduledoc """
  Os lexicons que o kernel conhece, indexados por NSID.

  O indice mora em `:persistent_term`, escrito uma vez pelo produto no boot e
  somente lido depois: lexicons so mudam quando alguem troca um arquivo, e
  reler JSON a cada escrita seria pagar uma checagem de schema com um disco.
  Leitura nao compra escrita, entao um leitor nunca ve metade de uma carga.

  A chamada de boot e `load/1`, com os diretorios de lexicon do produto, na
  ordem: o kernel primeiro, o produto depois. Um arquivo posterior substitui
  um anterior de mesmo `id`.
  """

  @table __MODULE__

  @doc """
  Carrega e resolve os lexicons dos diretorios e instala o indice.

  Devolve {indice, problemas} para o produto logar como quiser: o kernel nao
  loga, nao le config e nao decide o que fazer com um lexicon quebrado.
  """
  @spec load([String.t()]) :: {%{optional(String.t()) => map()}, [{String.t(), term()}]}
  def load(dirs) when is_list(dirs) do
    {entries, problems} = Ypy.Lexicon.load(dirs)

    records =
      Map.new(entries, fn {nsid, _document} ->
        {nsid, Ypy.Lexicon.record_schema(nsid, entries)}
      end)

    :persistent_term.put(@table, %{entries: entries, records: records})

    {entries, problems}
  end

  @doc "Os lexicons carregados, como mapa de NSID a documento."
  def all, do: cache().entries

  @doc "O documento de um NSID, ou nil."
  @spec get(String.t()) :: map() | nil
  def get(nsid) when is_binary(nsid), do: Map.get(cache().entries, nsid)
  def get(_nsid), do: nil

  @doc "O schema resolvido dos records de uma colecao, ou nil."
  @spec record(String.t()) :: map() | nil
  def record(collection) when is_binary(collection), do: Map.get(cache().records, collection)
  def record(_collection), do: nil

  @doc "Se o kernel guarda lexicon para a colecao."
  @spec knows?(String.t()) :: boolean()
  def knows?(collection) when is_binary(collection), do: record(collection) != nil
  def knows?(_collection), do: false

  defp cache, do: :persistent_term.get(@table, %{entries: %{}, records: %{}})
end
