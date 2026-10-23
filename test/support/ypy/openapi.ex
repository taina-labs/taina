defmodule Ypy.OpenAPI do
  @moduledoc """
  O leitor de `api/openapi.components.yaml` para o teste de conformidade.

  Um parser do subconjunto de YAML que o arquivo usa: mapeamentos aninhados
  pela indentacao, sequencias de bloco ("- "), sequencias de fluxo
  ("[a, b]"), o mapa de fluxo vazio ("{}") e escalares (null, booleanos,
  inteiros e strings, planas ou entre aspas). Ancoras, escalares de bloco e
  mapas de fluxo com conteudo ficam de fora: o arquivo e do kernel, e o
  subconjunto basta. O que foge do subconjunto levanta, para o teste falhar
  alto em vez de ler errado.
  """

  @doc "Os components do arquivo do repositorio, decodificados."
  @spec components() :: map()
  def components do
    File.cwd!()
    |> Path.join("api/openapi.components.yaml")
    |> File.read!()
    |> parse()
  end

  @doc "Decodifica o subconjunto de YAML usado pelo arquivo de components."
  @spec parse(String.t()) :: map()
  def parse(text) do
    {document, []} = text |> content_lines() |> nodes(0)
    document
  end

  # So as linhas de conteudo, como {indentacao, conteudo}. Linha vazia e
  # comentario integral saem; comentario de fim de linha nao e do subconjunto.
  defp content_lines(text) do
    for line <- String.split(text, "\n"),
        content = String.trim_leading(line),
        content != "" and not String.starts_with?(content, "#") do
      {String.length(line) - String.length(content), content}
    end
  end

  # Um bloco e a pilha de linhas com indentacao maior ou igual `min`; a
  # primeira decide se e sequencia, mapeamento ou escalar solto.
  defp nodes([{indent, content} | rest] = lines, min) when indent >= min do
    cond do
      String.starts_with?(content, "- ") -> sequence(lines, indent)
      pair?(content) -> mapping(lines, indent)
      true -> {scalar(content), rest}
    end
  end

  defp nodes(lines, _min), do: {%{}, lines}

  defp pair?(content) do
    String.contains?(content, ": ") or String.ends_with?(content, ":")
  end

  defp mapping(lines, indent), do: map_pairs(lines, indent, [])

  defp map_pairs([{indent, content} | rest], indent, acc) do
    {key, value} = split_pair(content)

    case value do
      nil ->
        {nested, rest} = nodes(rest, indent + 1)
        map_pairs(rest, indent, [{key, nested} | acc])

      value ->
        map_pairs(rest, indent, [{key, scalar(value)} | acc])
    end
  end

  defp map_pairs(lines, _indent, acc), do: {Map.new(acc), lines}

  defp split_pair(content) do
    case String.split(content, ": ", parts: 2) do
      [key, value] -> {key, value}
      [key] -> {String.slice(key, 0..-2//1), nil}
    end
  end

  defp sequence([{indent, "- " <> item} | rest], indent) do
    {first, rest} = nodes([{indent + 2, item} | rest], indent + 2)
    seq_items(rest, indent, [first])
  end

  defp seq_items([{indent, "- " <> item} | rest], indent, acc) do
    {item_node, rest} = nodes([{indent + 2, item} | rest], indent + 2)
    seq_items(rest, indent, [item_node | acc])
  end

  defp seq_items(lines, _indent, acc), do: {Enum.reverse(acc), lines}

  defp scalar("null"), do: nil
  defp scalar("true"), do: true
  defp scalar("false"), do: false
  defp scalar("{}"), do: %{}

  defp scalar(value) do
    cond do
      flow_seq?(value) -> flow_seq(value)
      quoted?(value) -> strip_quotes(value)
      Regex.match?(~r/^-?[0-9]+$/, value) -> String.to_integer(value)
      true -> value
    end
  end

  defp flow_seq?(value) do
    String.starts_with?(value, "[") and String.ends_with?(value, "]")
  end

  defp flow_seq(value) do
    value
    |> String.slice(1..-2//1)
    |> String.split(",")
    |> Enum.map(&scalar(String.trim(&1)))
  end

  defp quoted?(value) do
    quote_char = String.first(value)

    quote_char in ["\"", "'"] and String.ends_with?(value, quote_char) and
      String.length(value) > 1
  end

  defp strip_quotes(value) do
    quote_char = String.first(value)

    value
    |> String.slice(1..-2//1)
    |> String.replace("\\" <> quote_char, quote_char)
  end
end
