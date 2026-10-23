defmodule Ypy.RecordTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ypy.Cbor
  alias Ypy.Cbor.Bytes
  alias Ypy.Cid
  alias Ypy.Lexicon
  alias Ypy.Record

  @attrs [
    type: "ypy.file.v0",
    rkey: "6zjv4hbka5smq",
    actor: "ana.tekoa.br",
    created_at: 1_760_000_000_000_000,
    payload: %{"name" => "estatuto.pdf", "size" => 1024, "zona" => "praca"}
  ]

  @golden_bytes Base.decode16!(
                  "a564726b65796d367a6a763468626b6135736d716524747970656b7970792e66696c652e7630656163746f726c616e612e74656b6f612e6272677061796c6f6164a3646e616d656c657374617475746f2e7064666473697a65190400647a6f6e616570726163616a637265617465645f61741b000640b5eece0000",
                  case: :lower
                )

  @golden_cid "bafyreia4qkcdbfpmerjzmcpmcp36euutt76we6mdmipckxcwg2k456bwhy"

  @lexicon %{
    "id" => "ypy.file.v0",
    "defs" => %{
      "main" => %{
        "type" => "record",
        "record" => %{
          "type" => "object",
          "required" => ["name"],
          "properties" => %{
            "name" => %{"type" => "string", "maxLength" => 100},
            "size" => %{"type" => "integer", "minimum" => 0},
            "zona" => %{"type" => "string", "enum" => ["casa", "praca"]}
          }
        }
      }
    }
  }

  @schema Lexicon.record_schema("ypy.file.v0", %{"ypy.file.v0" => @lexicon})

  describe "build/1" do
    test "builds the envelope from attrs in any order" do
      record = Record.build(@attrs)

      assert record.type == "ypy.file.v0"
      assert record.rkey == "6zjv4hbka5smq"
      assert record.actor == "ana.tekoa.br"
      assert record.created_at == 1_760_000_000_000_000
      assert record.payload == %{"name" => "estatuto.pdf", "size" => 1024, "zona" => "praca"}
    end

    test "raises on an unknown or missing attr" do
      assert_raise ArgumentError, fn ->
        Record.build(Keyword.delete(@attrs, :payload))
      end

      assert_raise KeyError, fn ->
        Record.build(@attrs ++ [sobrenome: "nao"])
      end
    end
  end

  test "encode/1 yields exactly the golden bytes and CID" do
    assert {bytes, cid} = Record.encode(Record.build(@attrs))
    assert bytes == @golden_bytes
    assert Cid.to_string(cid) == @golden_cid
  end

  property "an envelope built twice from shuffled input yields identical bytes and CID" do
    check all(
            attrs_1 <- StreamData.shuffle(@attrs),
            attrs_2 <- StreamData.shuffle(@attrs),
            max_runs: 25
          ) do
      {bytes_1, cid_1} = Record.encode(Record.build(attrs_1))
      {bytes_2, cid_2} = Record.encode(Record.build(attrs_2))

      assert bytes_1 == bytes_2 and bytes_1 == @golden_bytes
      assert cid_1 == cid_2 and Cid.to_string(cid_1) == @golden_cid
    end
  end

  property "encode/1 and decode/1 round trip" do
    check all(
            name <- StreamData.string(:alphanumeric, min_length: 1, max_length: 20),
            size <- StreamData.integer(0..1_000_000),
            max_runs: 25
          ) do
      record =
        Record.build(
          type: "ypy.file.v0",
          rkey: "6zjv4hbka5smq",
          actor: "ana.tekoa.br",
          created_at: 1_760_000_000_000_000,
          payload: %{
            "name" => name,
            "size" => size,
            "bin" => %Bytes{data: "ola"},
            "cid" => Cid.from_data("ola")
          }
        )

      {bytes, cid} = Record.encode(record)
      assert Cid.from_data(bytes) == cid
      assert Record.decode(bytes) == {:ok, record}
    end
  end

  test "decode/1 refuses what is not an envelope" do
    assert Record.decode(<<1, 2, 3>>) == {:error, :malformed}
    assert Record.decode(Cbor.encode("ola")) == {:error, :malformed}

    sem_payload = %{
      "$type" => "ypy.file.v0",
      "rkey" => "6zjv4hbka5smq",
      "actor" => "ana.tekoa.br",
      "created_at" => 1_760_000_000_000_000
    }

    assert Record.decode(Cbor.encode(sem_payload)) == {:error, :malformed}

    com_extra = sem_payload |> Map.put("payload", %{}) |> Map.put("extra", 1)

    assert Record.decode(Cbor.encode(com_extra)) == {:error, :malformed}
  end

  describe "check/2" do
    test ":ok when the envelope and the payload pass" do
      assert Record.check(Record.build(@attrs), @schema) == :ok
    end

    test "an unknown collection is not a shape error" do
      assert Record.check(Record.build(@attrs), nil) == {:error, :unknown_collection}
    end

    test "a payload error comes prefixed in the path" do
      record = Record.build(Keyword.put(@attrs, :payload, %{"name" => 7}))

      assert Record.check(record, @schema) == {:error, [{["payload", "name"], :expected_string}]}
    end

    test "an envelope error comes with the control field path" do
      record = Record.build(Keyword.put(@attrs, :rkey, "nao-e-tid"))

      assert Record.check(record, @schema) == {:error, [{["rkey"], :bad_tid}]}

      record = Record.build(Keyword.put(@attrs, :created_at, -1))

      assert Record.check(record, @schema) == {:error, [{["created_at"], :below_minimum}]}
    end

    test "two mistakes, two errors" do
      record =
        Record.build(Keyword.merge(@attrs, rkey: "nao-e-tid", payload: %{"name" => 7}))

      assert Record.check(record, @schema) ==
               {:error, [{["rkey"], :bad_tid}, {["payload", "name"], :expected_string}]}
    end
  end
end
