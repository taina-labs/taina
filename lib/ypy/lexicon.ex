defmodule Ypy.Lexicon do
  @moduledoc """
  Carrega e indexa definicoes de lexicon (formato JSON do ATProto).

  As definicoes sao dados, nao codigo: um lexicon e um mapa decodificado de
  JSON com `id`, `defs` e, para colecoes de record, um def de `"type"` igual
  a `"record"` cuja chave `"record"` guarda o schema do payload. Produtos
  estendem o protocolo derrubando os proprios arquivos em um diretorio
  proprio e passando os dois diretorios para `Ypy.Lexicon.Registry.load/1`
  no boot; o kernel nunca aprende collection id de produto.

  `load/1` le os diretorios na ordem dada e indexa pelo `id` de cada arquivo,
  com um diretorio posterior substituindo um anterior: sobrescrever um
  lexicon do kernel e uma edicao local, nao um fork. Um arquivo que nao pode
  ser lido, que nao e JSON ou que nao declara `id` vira um problema na lista
  devolvida, nao uma excecao, porque um lexicon quebrado de produto nao pode
  derrubar um boot que ja funcionava.

  A resolucao de `ref` e `union` acontece uma vez, no boot: seguir referencias
  e uma funcao pura dos documentos, entao o schema resolvido de cada colecao
  nao muda enquanto os documentos nao mudarem. Um `ref` que aponta para um
  lexicon ausente fica como esta, e o validador aceita o que nao pode seguir;
  uma referencia pendente degrada aquela subarvore para "sem checagem" em vez
  de recusar escritas.
  """

  @dialyzer :no_opaque

  @doc """
  Le todo lexicon de cada diretorio, na ordem, e devolve {indice, problemas}.

  O indice e um mapa de NSID a documento decodificado. `problemas` e uma
  lista de {caminho, motivo}, com motivo em `{:unreadable, motivo}`,
  `:no_id` e `{:bad_json, motivo}`.
  """
  @spec load([String.t()]) :: {%{optional(String.t()) => map()}, [{String.t(), term()}]}
  def load(dirs) when is_list(dirs) do
    dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.json")))
    |> Enum.uniq()
    |> Enum.reduce({%{}, []}, &read/2)
  end

  @doc """
  O schema resolvido dos records de uma colecao, ou nil quando o indice nao
  tem lexicon para ela.

  Resolvido significa: os nos `ref` e `union` ja apontam para os schemas que
  eles nomeiam, de modo que `Ypy.Lexicon.Validate` nunca precisa olhar o
  indice. Um documento sem def de record resolve a nil e a colecao le como
  desconhecida.
  """
  @spec record_schema(String.t(), %{optional(String.t()) => map()}) :: map() | nil
  def record_schema(collection, index) when is_binary(collection) and is_map(index) do
    with %{"defs" => defs} when is_map(defs) <- Map.get(index, collection),
         {_name, %{"record" => schema}} when is_map(schema) <-
           Enum.find(defs, fn {_name, def} -> def["type"] == "record" end) do
      resolve(schema, Map.get(index, collection), MapSet.new(), index)
    else
      _ -> nil
    end
  end

  defp read(path, {index, problems}) do
    case File.read(path) do
      {:ok, body} ->
        read_body(path, body, index, problems)

      {:error, reason} ->
        {index, [{path, {:unreadable, reason}} | problems]}
    end
  end

  defp read_body(path, body, index, problems) do
    case JSON.decode(body) do
      {:ok, %{"id" => nsid} = doc} when is_binary(nsid) ->
        {Map.put(index, nsid, doc), problems}

      {:ok, _document} ->
        {index, [{path, :no_id} | problems]}

      {:error, reason} ->
        {index, [{path, {:bad_json, reason}} | problems]}
    end
  end

  # Cada no e resolvido contra o documento de onde veio, nao contra o da
  # caminhada: um "#def" dentro de uma definicao puxada de outro lexicon
  # nomeia um def daquele lexicon, nao do que comecou a caminhada.
  defp resolve(%{"type" => "ref", "ref" => ref}, document, seen, entries) when is_binary(ref) do
    case lookup(ref, document, seen, entries) do
      {nil, _document} ->
        %{"type" => "ref", "ref" => ref}

      {target, target_document} ->
        resolve(target, target_document, MapSet.put(seen, ref), entries)
    end
  end

  defp resolve(%{"type" => "union"} = node, document, seen, entries) do
    node
    |> Map.put("defs", Map.get(document, "defs", %{}))
    |> put_variants(document, seen, entries)
  end

  defp resolve(%{"properties" => properties} = node, document, seen, entries) when is_map(properties) do
    Map.put(
      node,
      "properties",
      Map.new(properties, fn {key, child} ->
        {key, resolve(child, document, seen, entries)}
      end)
    )
  end

  defp resolve(%{"items" => items} = node, document, seen, entries),
    do: Map.put(node, "items", resolve(items, document, seen, entries))

  defp resolve(node, _document, _seen, _entries), do: node

  defp put_variants(node, document, seen, entries) do
    variants =
      [node["ref"] | Map.get(node, "refs", [])]
      |> Enum.reject(&is_nil/1)
      |> Enum.flat_map(fn ref ->
        case lookup(ref, document, seen, entries) do
          {nil, _document} ->
            []

          {target, target_document} ->
            [{ref, resolve(target, target_document, MapSet.put(seen, ref), entries)}]
        end
      end)

    Map.put(node, "variants", Map.new(variants))
  end

  # Um ref em curso de seguida e deixado como esta, para dois lexicons que se
  # referenciam terminarem em vez de resolver para sempre.
  defp lookup(ref, document, seen, entries) do
    if MapSet.member?(seen, ref) do
      {nil, document}
    else
      foreign(ref, document, entries)
    end
  end

  defp foreign("#" <> name, document, _entries), do: {get_in(document, ["defs", name]), document}

  defp foreign(ref, _document, entries) do
    case String.split(ref, "#", parts: 2) do
      [nsid] -> def_of(entries, nsid, "main")
      [nsid, name] -> def_of(entries, nsid, name)
    end
  end

  # Le dos entries da resolucao, nao do indice carregado, para resolver uma
  # geracao de documentos por vez.
  defp def_of(entries, nsid, def_name) do
    case Map.fetch(entries, nsid) do
      {:ok, document} -> {get_in(document, ["defs", def_name]), document}
      :error -> {nil, nil}
    end
  end
end
