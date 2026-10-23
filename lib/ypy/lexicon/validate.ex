defmodule Ypy.Lexicon.Validate do
  @moduledoc """
  Confere o payload de um record contra a definicao do lexicon da colecao.

  Puro e total: recebe a definicao como argumento, nao le registro, nao toca
  processo e nunca levanta. Cada desacordo volta como um caminho e um motivo,
  um erro por deslize, para o chamador dizer ao cliente qual campo errou:

      iex> post = %{"type" => "object", "required" => ["text"],
      ...>          "properties" => %{"text" => %{"type" => "string"}}}
      iex> Ypy.Lexicon.Validate.validate(post, %{"text" => "oi"})
      :ok
      iex> Ypy.Lexicon.Validate.validate(post, %{})
      {:error, [{["text"], :required}]}

  As regras implementadas sao as que os lexicons usam: `object` (com
  `required`, `nullable`, `properties`), `array` (com `items`, `minLength`,
  `maxLength`), `string` (com `format`, `enum`, `const`, `minLength`,
  `maxLength`, `maxGraphemes`), `integer` (`minimum`, `maximum`, `const`),
  `boolean`, `float`, `number`, `unknown`, `bytes`, `cid-link`, `blob`,
  `token`, `ref` e `union`.

  Um campo que o lexicon nao declara e ignorado, nao recusado: um record
  escrito por um lexicon mais novo tem de continuar passando pela copia mais
  antiga que o servidor guarda.

  O `maxLength` de uma string conta bytes UTF-8, a unidade da especificacao, e
  `maxGraphemes` e a regra separada para o que a pessoa le. Um valor acima do
  maximo de bytes e recusado antes do grafo ser contado.

  `bytes`, `cid-link`, `blob` e `token` sao aceitos pela forma, nao parseados.
  O que o lexicon declara sobre eles, porem, e medido aqui mesmo: `bytes`
  contra `maxLength` (contando o que o `$bytes` em base64 decodifica), `blob`
  contra `maxSize` e `accept`. O tamanho que um blob declara e a afirmacao do
  cliente sobre bytes que este modulo nao ve; quem aplica o tamanho real e
  onde os bytes sao lidos, no upload do produto.

  Um `ref` ou membro de union que nao pode ser resolvido, e qualquer no
  debaixo dele, e pulado em vez de falhar: uma referencia quebrada no lexicon
  de um produto nao pode recusar toda escrita.
  """

  @doc "Valida um valor contra uma definicao de lexicon."
  @spec validate(map() | nil, term()) :: :ok | {:error, [{[term()], atom() | tuple()}]}
  def validate(nil, _value), do: :ok
  def validate(schema, value), do: result(errors(schema, value, []))

  defp result([]), do: :ok
  defp result(errors), do: {:error, errors}

  defp errors(%{"type" => "object"} = schema, value, path) when is_map(value) do
    properties = Map.get(schema, "properties", %{})
    required = schema["required"] || []
    nullable = nullable(schema)

    Enum.flat_map(required, fn field ->
      if Map.has_key?(value, field) and not is_nil(value[field]),
        do: [],
        else: [{path ++ [field], :required}]
    end) ++
      errors_in(value, properties, path, nullable, required)
  end

  defp errors(%{"type" => "object"}, _value, path), do: [{path, :expected_object}]

  defp errors(%{"type" => "array"} = schema, value, path) when is_list(value) do
    length_errors(schema, value, path) ++ item_errors(Map.get(schema, "items"), value, path)
  end

  defp errors(%{"type" => "array"}, _value, path), do: [{path, :expected_array}]

  defp errors(%{"type" => "string"} = schema, value, path) when is_binary(value) do
    format_errors(schema["format"], value, path) ++
      const_errors(schema["const"], value, path) ++
      enum_errors(schema["enum"], value, path) ++
      string_length_errors(schema, value, path)
  end

  defp errors(%{"type" => "string"}, _value, path), do: [{path, :expected_string}]

  defp errors(%{"type" => "integer"} = schema, value, path) when is_integer(value) do
    const_errors(schema["const"], value, path) ++
      enum_errors(schema["enum"], value, path) ++
      range_errors(schema, value, path)
  end

  defp errors(%{"type" => "integer"}, _value, path), do: [{path, :expected_integer}]

  defp errors(%{"type" => "float"} = schema, value, path) when is_float(value),
    do: const_errors(schema["const"], value, path)

  defp errors(%{"type" => "float"}, _value, path), do: [{path, :expected_float}]

  defp errors(%{"type" => "number"} = schema, value, path) when is_integer(value) or is_float(value),
    do: const_errors(schema["const"], value, path)

  defp errors(%{"type" => "number"}, _value, path), do: [{path, :expected_number}]
  defp errors(%{"type" => "boolean"}, value, _path) when is_boolean(value), do: []
  defp errors(%{"type" => "boolean"}, _value, path), do: [{path, :expected_boolean}]
  defp errors(%{"type" => "unknown"}, _value, _path), do: []

  defp errors(%{"type" => "union"} = schema, value, path) when is_map(value) do
    allowed = Enum.reject([schema["ref"] | Map.get(schema, "refs", [])], &is_nil/1)

    case value["$type"] do
      nil -> [{path, :missing_type}]
      type -> union_errors(schema, allowed, type, value, path)
    end
  end

  defp errors(%{"type" => "union"}, _value, path), do: [{path, :expected_object}]

  defp errors(%{"type" => "ref"}, _value, _path), do: []

  defp errors(%{"type" => "bytes"} = schema, value, path) when is_binary(value),
    do: bounds(schema, path, byte_size(value))

  defp errors(%{"type" => "bytes"} = schema, value, path) when is_map(value) do
    with false <- is_struct(value),
         {:ok, b64} when is_binary(b64) <- Map.fetch(value, "$bytes"),
         {:ok, data} <- Base.decode64(b64) do
      bounds(schema, path, byte_size(data))
    else
      _ -> []
    end
  end

  defp errors(%{"type" => "bytes"}, _value, _path), do: []

  defp errors(%{"type" => "blob"} = schema, value, path) when is_map(value) do
    if is_struct(value) do
      []
    else
      blob_size_errors(schema["maxSize"], value["size"], path) ++
        accept_errors(schema["accept"], value["mimeType"], path)
    end
  end

  defp errors(%{"type" => "blob"}, _value, _path), do: []

  defp errors(%{"type" => type}, _value, _path) when type in ["cid-link", "token"], do: []

  defp errors(_def, _value, path), do: [{path, :unrecognized_definition}]

  defp union_errors(schema, allowed, type, value, path) do
    case resolve(schema, allowed, type) do
      {:ok, target} -> errors(target, value, path)
      :foreign -> []
      :unknown -> if(schema["closed"] == true, do: [{path, :unknown_type}], else: [])
    end
  end

  defp item_errors(nil, _value, _path), do: []

  defp item_errors(items, value, path) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {element, index} -> errors(items, element, path ++ [index]) end)
  end

  defp nullable(schema) do
    case Map.get(schema, "nullable") do
      list when is_list(list) -> list
      _ -> []
    end
  end

  # Um null em campo required ou nullable nao ganha checagem de tipo por
  # cima: o :required ja disse o deslize, e repeti-lo com outro motivo e
  # contar um erro duas vezes.
  defp errors_in(value, properties, path, nullable, required) do
    Enum.flat_map(properties, fn {key, schema} ->
      case Map.fetch(value, key) do
        {:ok, nil} -> nil_value_errors(schema, key, path, nullable, required)
        {:ok, nested} -> errors(schema, nested, path ++ [key])
        :error -> []
      end
    end)
  end

  defp nil_value_errors(schema, key, path, nullable, required) do
    if key in nullable or key in required,
      do: [],
      else: errors(schema, nil, path ++ [key])
  end

  defp resolve(schema, allowed, type) do
    {target, fragment} = split_ref(type)

    cond do
      type in allowed -> variant(schema, type, fragment)
      target == "" -> :unknown
      is_nil(fragment) -> resolve_target(schema, allowed, target)
      target in allowed -> variant(schema, target, fragment)
      ("#" <> fragment) in allowed -> variant(schema, "#" <> fragment, fragment)
      true -> :unknown
    end
  end

  defp split_ref(type) do
    case String.split(type, "#", parts: 2) do
      ["#" <> name] -> {"", name}
      [nsid] -> {nsid, nil}
      [nsid, name] -> {nsid, name}
    end
  end

  defp resolve_target(schema, allowed, target) do
    if target in allowed, do: variant(schema, target, nil), else: :unknown
  end

  defp variant(schema, ref, fragment) do
    case Map.get(Map.get(schema, "variants", %{}), ref) do
      nil -> local_def(schema, fragment)
      target -> {:ok, target}
    end
  end

  defp local_def(schema, fragment) do
    case Map.get(Map.get(schema, "defs", %{}), fragment) do
      nil -> :foreign
      target -> {:ok, target}
    end
  end

  defp string_length_errors(schema, value, path) do
    case bounds(schema, path, byte_size(value)) do
      [{_, :too_long}] = too_long -> too_long
      size_errors -> size_errors ++ grapheme_errors(schema["maxGraphemes"], value, path)
    end
  end

  defp length_errors(schema, value, path) when is_list(value) do
    bounds(schema, path, length(value))
  end

  defp bounds(schema, path, size) do
    case schema["minLength"] do
      nil -> []
      min when size < min -> [{path, :too_short}]
      _ -> []
    end ++
      case schema["maxLength"] do
        nil -> []
        max when size > max -> [{path, :too_long}]
        _ -> []
      end
  end

  defp blob_size_errors(nil, _size, _path), do: []

  defp blob_size_errors(max, size, path) when is_integer(size) and size > max, do: [{path, :too_large}]

  defp blob_size_errors(_max, _size, _path), do: []

  defp accept_errors(nil, _mime, _path), do: []

  defp accept_errors(accepted, mime, path) when is_binary(mime) do
    if Enum.any?(List.wrap(accepted), &accepts?(&1, mime)),
      do: [],
      else: [{path, :bad_mime_type}]
  end

  defp accept_errors(_accepted, _mime, _path), do: []

  defp accepts?(pattern, mime) when is_binary(pattern) do
    cond do
      pattern == "*/*" ->
        true

      pattern == "*" ->
        String.contains?(mime, "/")

      String.ends_with?(pattern, "/*") ->
        String.starts_with?(mime, String.trim_trailing(pattern, "*"))

      String.starts_with?(pattern, "*/") ->
        String.ends_with?(mime, String.trim_leading(pattern, "*"))

      true ->
        pattern == mime
    end
  end

  defp accepts?(_pattern, _mime), do: false

  defp grapheme_errors(nil, _value, _path), do: []

  defp grapheme_errors(max, value, path) do
    if String.length(value) > max, do: [{path, :too_many_graphemes}], else: []
  end

  defp range_errors(schema, value, path) do
    case schema["minimum"] do
      nil -> []
      min when value < min -> [{path, :below_minimum}]
      _ -> []
    end ++
      case schema["maximum"] do
        nil -> []
        max when value > max -> [{path, :above_maximum}]
        _ -> []
      end
  end

  defp const_errors(nil, _value, _path), do: []

  defp const_errors(const, value, path), do: if(const === value, do: [], else: [{path, :not_const}])

  defp enum_errors(nil, _value, _path), do: []

  defp enum_errors(allowed, value, path), do: if(value in allowed, do: [], else: [{path, :not_in_enum}])

  defp format_errors(nil, _value, _path), do: []

  defp format_errors("datetime", value, path) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} ->
        []

      {:error, reason} ->
        case Date.from_iso8601(value) do
          {:ok, _date} ->
            []

          {:error, date_reason} ->
            [{path, {:bad_datetime, reason, date_reason}}]
        end
    end
  end

  defp format_errors("at-uri", value, path) do
    if String.starts_with?(value, "at://"), do: [], else: [{path, :bad_at_uri}]
  end

  defp format_errors("did", value, path) do
    if String.starts_with?(value, "did:"), do: [], else: [{path, :bad_did}]
  end

  defp format_errors("handle", value, path) do
    if value == "" or String.contains?(value, "/"), do: [{path, :bad_handle}], else: []
  end

  defp format_errors("nsid", value, path) do
    segments = String.split(value, ".")

    if length(segments) < 3 or
         Enum.any?(segments, &(&1 == "" or String.match?(&1, ~r/^[0-9]/))) do
      [{path, :bad_nsid}]
    else
      []
    end
  end

  defp format_errors("tid", value, path) do
    if String.match?(value, ~r/^[234567abcdefghij][234567abcdefghijklmnopqrstuvwxyz]{12}$/),
      do: [],
      else: [{path, :bad_tid}]
  end

  defp format_errors("record-key", value, path) do
    if value in ["self"] or String.match?(value, ~r/^[a-zA-Z0-9._~:-]{1,512}$/),
      do: [],
      else: [{path, :bad_record_key}]
  end

  defp format_errors("uri", value, path) do
    case URI.new(value) do
      {:ok, %URI{scheme: nil}} -> [{path, :bad_uri}]
      {:ok, _uri} -> []
      {:error, _reason} -> [{path, :bad_uri}]
    end
  end

  defp format_errors("language", value, path) do
    if String.match?(value, ~r/^[a-zA-Z]{2,3}(-[a-zA-Z0-9]{2,8})*$/),
      do: [],
      else: [{path, :bad_language}]
  end

  defp format_errors("cid", value, path) do
    if Ypy.Cid.safe_parse(value) == :error, do: [{path, :bad_cid}], else: []
  end

  defp format_errors("at-identifier", value, path) do
    cond do
      String.starts_with?(value, "at://") -> []
      String.starts_with?(value, "did:") -> []
      String.contains?(value, "@") -> []
      true -> [{path, :bad_at_identifier}]
    end
  end

  defp format_errors(format, _value, path), do: [{path, {:unsupported_format, format}}]
end
