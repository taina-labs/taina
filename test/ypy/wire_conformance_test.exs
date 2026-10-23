defmodule Ypy.Wire.ConformanceTest do
  @moduledoc """
  A guarda contra a deriva silenciosa entre o mundo CBOR (dados) e o mundo
  HTTP JSON (fio), o teste de conformidade do kernel (RFC_006 secao 6): para
  cada lexicon em `priv/lexicons`, uma amostra serializa pelo mundo CBOR, e
  todo campo do lexicon aparece como propriedade do component do fio, com o
  tipo mapeado.
  """

  use ExUnit.Case, async: true

  alias Ypy.Cid
  alias Ypy.Lexicon
  alias Ypy.OpenAPI
  alias Ypy.Record
  alias Ypy.Tid

  @actor "ana@tekoa.br"
  @agora 1_700_000_000_000_000

  test "todo campo dos lexicons do kernel e propriedade do component do fio" do
    {entries, problems} = Lexicon.load([lexicons()])
    assert problems == []

    assert components = OpenAPI.components()["components"]["schemas"]

    entries
    |> Enum.sort()
    |> Enum.each(fn {nsid, _document} ->
      schema = Lexicon.record_schema(nsid, entries)
      assert schema, "#{nsid}: o lexicon nao declara record"

      serialize(nsid, schema)

      component = component(components, nsid)

      schema["properties"]
      |> Enum.sort()
      |> Enum.each(fn {field, node} ->
        property = component["properties"][field]

        assert property, "#{nsid}: o campo #{field} nao e propriedade do component"

        assert matches?(node, property),
               "#{nsid}: o campo #{field} pede #{inspect(expected(node))}, " <>
                 "o component tem #{inspect(property)}"
      end)
    end)
  end

  defp lexicons, do: Path.join(File.cwd!(), "priv/ypy/lexicons")

  # A metade CBOR da conformidade: a amostra valida contra o lexicon e o
  # envelope serializa com o CID saindo. Campo de union fica de fora da
  # amostra, porque o valor de union e um mapa com $type e variante de
  # string nao tem mapa que valide; o campo segue na checagem do component.
  defp serialize(nsid, schema) do
    payload =
      schema["properties"]
      |> Enum.reject(fn {_field, node} -> node["type"] == "union" end)
      |> Map.new(fn {field, node} -> {field, sample(node)} end)

    record =
      Record.build(type: nsid, rkey: rkey(), actor: @actor, created_at: @agora, payload: payload)

    assert Record.check(record, schema) == :ok
    assert {_bytes, cid} = Record.encode(record)
    assert String.starts_with?(Cid.to_string(cid), "b")
  end

  # A amostra de cada no do lexicon, para o payload validar de primeira.
  defp sample(%{"type" => "string"} = node) do
    cond do
      enum = node["enum"] -> hd(enum)
      const = node["const"] -> const
      node["format"] == "tid" -> rkey()
      node["format"] == "cid" -> cid()
      node["format"] == "datetime" -> "2026-10-12T00:00:00Z"
      true -> "registro"
    end
  end

  defp sample(%{"type" => "cid-link"}), do: cid()
  defp sample(%{"type" => "integer"}), do: 1
  defp sample(%{"type" => "boolean"}), do: true
  defp sample(%{"type" => "bytes"}), do: "bytes"
  defp sample(%{"type" => "unknown"}), do: "registro"
  defp sample(%{"type" => "ref"}), do: "registro"
  defp sample(%{"type" => "object"}), do: %{}
  defp sample(%{"type" => "array"}), do: []

  defp rkey do
    {rkey, _} = Tid.next(0, @agora, 0)
    rkey
  end

  defp cid, do: "conformidade" |> Cid.from_data() |> Cid.to_string()

  # O mapeamento de tipos do lexicon para o fio (RFC_006 secao 6): o par
  # chave e valor que a propriedade do component precisa carregar. Descricoes
  # e outros extras ficam livres; o que ela declara de tipo tem de casar.
  defp expected(%{"type" => "string"} = node) do
    [{"type", "string"}] ++
      Enum.concat(
        for key <- ["minLength", "maxLength", "minGraphemes", "maxGraphemes", "enum"],
            value = node[key],
            do: [{key, value}]
      )
  end

  defp expected(%{"type" => "cid-link"}), do: [{"type", "string"}, {"format", "cid"}]
  defp expected(%{"type" => "integer"}), do: [{"type", "integer"}]
  defp expected(%{"type" => "boolean"}), do: [{"type", "boolean"}]

  defp expected(%{"type" => "union"} = node) do
    arms =
      node
      |> Map.get("variants", %{})
      |> Enum.sort()
      |> Enum.map(fn {_ref, variant} -> Map.new(expected(variant)) end)

    [{"oneOf", arms}]
  end

  # Ref que nao fechou e no sem tipo conhecido: o validador nao checa, e o
  # fio nao afirma.
  defp expected(_node), do: []

  defp matches?(node, property) do
    Enum.all?(expected(node), fn {key, value} -> property[key] == value end)
  end

  # A convencao de nome do component de um lexicon do kernel: o nome da
  # colecao em CamelCase mais "Record" (ypy.file.v0 -> FileRecord).
  defp component(components, nsid) do
    name =
      nsid
      |> String.split(".")
      |> Enum.at(1)
      |> Macro.camelize()
      |> Kernel.<>("Record")

    assert {:ok, component} = Map.fetch(components, name)
    component
  end
end
