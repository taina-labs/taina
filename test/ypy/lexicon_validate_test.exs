defmodule Ypy.Lexicon.ValidateTest do
  use ExUnit.Case, async: true

  alias Ypy.Lexicon.Validate

  defp errors(schema, value) do
    case Validate.validate(schema, value) do
      :ok -> []
      {:error, errors} -> errors
    end
  end

  test "a required field that is missing or null is one error" do
    schema = %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{"name" => %{"type" => "string"}}
    }

    assert errors(schema, %{}) == [{["name"], :required}]
    assert errors(schema, %{"name" => nil}) == [{["name"], :required}]
  end

  test "a null on a required field is reported once, not twice" do
    schema = %{
      "type" => "object",
      "required" => ["name"],
      "properties" => %{"name" => %{"type" => "string"}}
    }

    assert length(errors(schema, %{"name" => nil})) == 1
  end

  test "a null on a nullable field is legal and on a plain optional one is a type error" do
    schema = %{
      "type" => "object",
      "nullable" => ["bio"],
      "properties" => %{
        "bio" => %{"type" => "string"},
        "name" => %{"type" => "string"}
      }
    }

    assert errors(schema, %{"bio" => nil}) == []
    assert errors(schema, %{"name" => nil}) == [{["name"], :expected_string}]
  end

  test "a field the lexicon does not declare is ignored" do
    schema = %{
      "type" => "object",
      "properties" => %{"name" => %{"type" => "string"}}
    }

    assert errors(schema, %{"name" => "ana", "extra" => 123}) == []
  end

  test "a non-map value for an object is one error at the object path" do
    schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}

    assert errors(schema, "ola") == [{[], :expected_object}]
  end

  test "string bounds count bytes and graphemes separately" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string", "maxLength" => 4, "maxGraphemes" => 3}
      }
    }

    assert errors(schema, %{"name" => "abcdef"}) == [{["name"], :too_long}]

    assert errors(schema, %{"name" => "aa"}) == []

    assert errors(schema, %{"name" => "aaa"}) == []

    assert errors(schema, %{"name" => "aaaa"}) == [{["name"], :too_many_graphemes}]
  end

  test "an over-long string is refused on bytes before the grapheme count" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string", "maxLength" => 2, "maxGraphemes" => 1}
      }
    }

    assert errors(schema, %{"name" => "aaaa"}) == [{["name"], :too_long}]
  end

  test "integer bounds and enum" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "size" => %{"type" => "integer", "minimum" => 1, "maximum" => 10},
        "kind" => %{"type" => "integer", "enum" => [1, 2, 3]}
      }
    }

    assert errors(schema, %{"size" => 0}) == [{["size"], :below_minimum}]
    assert errors(schema, %{"size" => 11}) == [{["size"], :above_maximum}]
    assert errors(schema, %{"kind" => 4}) == [{["kind"], :not_in_enum}]
    assert errors(schema, %{"kind" => "2"}) == [{["kind"], :expected_integer}]
  end

  test "const and enum on strings" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "zona" => %{"type" => "string", "const" => "praca"},
        "papel" => %{"type" => "string", "enum" => ["zelador", "morador"]}
      }
    }

    assert errors(schema, %{"zona" => "casa"}) == [{["zona"], :not_const}]
    assert errors(schema, %{"papel" => "dono"}) == [{["papel"], :not_in_enum}]
  end

  test "array bounds and per-item paths" do
    schema = %{
      "type" => "object",
      "properties" => %{
        "tags" => %{
          "type" => "array",
          "minLength" => 1,
          "maxLength" => 3,
          "items" => %{"type" => "string", "format" => "tid"}
        }
      }
    }

    assert errors(schema, %{"tags" => []}) == [{["tags"], :too_short}]
    validos = ["aaaaaaaaaaaaa", "aaaaaaaaaaaaa", "aaaaaaaaaaaaa", "aaaaaaaaaaaaa"]

    assert errors(schema, %{"tags" => validos}) == [{["tags"], :too_long}]

    assert errors(schema, %{"tags" => ["aaaaaaaaaaaaa", 7]}) == [
             {["tags", 1], :expected_string}
           ]
  end

  test "formats: datetime, nsid, tid, handle, did, cid" do
    datetime_schema = %{"type" => "string", "format" => "datetime"}

    assert errors(datetime_schema, "2026-06-15T10:00:00Z") == []
    assert errors(datetime_schema, "2026-06-15") == []

    assert {:error, [{[], {:bad_datetime, _, _}}]} = Validate.validate(datetime_schema, "amanha")

    nsid_schema = %{"type" => "string", "format" => "nsid"}

    assert errors(nsid_schema, "ypy.file.v0") == []
    assert errors(nsid_schema, "file.v0") == [{[], :bad_nsid}]
    assert errors(nsid_schema, "ypy.1file.v0") == [{[], :bad_nsid}]

    tid_schema = %{"type" => "string", "format" => "tid"}

    assert errors(tid_schema, "6zjv4hbka5smq") == []
    assert errors(tid_schema, "0zjv4hbka5smq") == [{[], :bad_tid}]
    assert errors(tid_schema, "6zjv4hbka5sm") == [{[], :bad_tid}]

    handle_schema = %{"type" => "string", "format" => "handle"}

    assert errors(handle_schema, "ana.tekoa.br") == []
    assert errors(handle_schema, "") == [{[], :bad_handle}]
    assert errors(handle_schema, "ana/tekoa") == [{[], :bad_handle}]

    did_schema = %{"type" => "string", "format" => "did"}

    assert errors(did_schema, "did:web:tekoa.br") == []
    assert errors(did_schema, "web:tekoa.br") == [{[], :bad_did}]

    cid_schema = %{"type" => "string", "format" => "cid"}

    assert errors(cid_schema, "bafyreia4qkcdbfpmerjzmcpmcp36euutt76we6mdmipckxcwg2k456bwhy") == []
    assert errors(cid_schema, "nao-e-cid") == [{[], :bad_cid}]
  end

  test "a union checks the member the value names and stays open by default" do
    schema = %{
      "type" => "union",
      "refs" => ["#textTag", "ypy.tag.v0#tagRef"],
      "defs" => %{"textTag" => %{"type" => "string", "maxLength" => 3}},
      "variants" => %{
        "#textTag" => %{
          "type" => "object",
          "properties" => %{"value" => %{"type" => "string", "maxLength" => 3}}
        },
        "ypy.tag.v0#tagRef" => %{
          "type" => "object",
          "properties" => %{"value" => %{"type" => "integer"}}
        }
      }
    }

    assert errors(schema, %{"$type" => "#textTag", "value" => "oi"}) == []

    assert errors(schema, %{"$type" => "#textTag", "value" => "oi demais"}) == [
             {["value"], :too_long}
           ]

    assert errors(schema, %{"$type" => "ypy.tag.v0#tagRef", "value" => 7}) == []

    assert errors(schema, %{"$type" => "ypy.tag.v0#tagRef", "value" => "7"}) == [
             {["value"], :expected_integer}
           ]

    assert errors(schema, %{}) == [{[], :missing_type}]

    assert errors(schema, %{"$type" => "novo.lexicon.v0#futuro"}) == []

    fechado = Map.put(schema, "closed", true)

    assert errors(fechado, %{"$type" => "novo.lexicon.v0#futuro"}) == [{[], :unknown_type}]
  end

  test "bytes are measured by what the base64 decodes to" do
    schema = %{"type" => "bytes", "maxLength" => 4}

    assert errors(schema, Base.encode64("ola")) == []
    assert errors(schema, Base.encode64("ola, mundo")) == [{[], :too_long}]
    assert errors(schema, %Ypy.Cbor.Bytes{data: "ola"}) == []
  end

  test "a blob checks the size claim and the mime accept list" do
    schema = %{
      "type" => "blob",
      "maxSize" => 100,
      "accept" => ["image/*", "text/plain"]
    }

    assert errors(schema, %{"size" => 99, "mimeType" => "image/png"}) == []
    assert errors(schema, %{"size" => 101, "mimeType" => "image/png"}) == [{[], :too_large}]
    assert errors(schema, %{"size" => 99, "mimeType" => "video/mp4"}) == [{[], :bad_mime_type}]

    assert errors(schema, %{"size" => 101, "mimeType" => "video/mp4"}) == [
             {[], :too_large},
             {[], :bad_mime_type}
           ]
  end

  test "two mistakes in two fields are two errors, each with its own path" do
    schema = %{
      "type" => "object",
      "required" => ["name", "size"],
      "properties" => %{
        "name" => %{"type" => "string", "maxLength" => 3},
        "size" => %{"type" => "integer", "minimum" => 1}
      }
    }

    assert errors(schema, %{"name" => "demasiado", "size" => 0}) == [
             {["name"], :too_long},
             {["size"], :below_minimum}
           ]
  end

  test "an unknown definition is refused and an unknown type is accepted" do
    assert errors(%{"type" => "mistery"}, 1) == [{[], :unrecognized_definition}]
    assert errors(%{"type" => "unknown"}, %{"whatever" => "goes"}) == []
    assert errors(%{"type" => "token"}, "qualquer") == []
    assert errors(%{"type" => "cid-link"}, "bafyreia") == []
  end

  test "nil schema accepts anything, the way an unchecked ref degrades" do
    assert Validate.validate(nil, %{"anything" => :at_all}) == :ok
  end
end
