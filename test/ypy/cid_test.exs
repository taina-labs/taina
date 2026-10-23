defmodule Ypy.CidTest do
  use ExUnit.Case, async: true

  alias Ypy.Cbor
  alias Ypy.Cid

  test "matches the cids computed by the reference ipld implementation" do
    assert %{"a" => 1} |> Cbor.encode() |> Cid.from_data() |> Cid.to_string() ==
             "bafyreihltcnuuyqp2jm24aqydpnlj7b6w3ogwrplomrjtg5rifv44mmjey"

    assert %{"hello" => "world"} |> Cbor.encode() |> Cid.from_data() |> Cid.to_string() ==
             "bafyreidykglsfhoixmivffc5uwhcgshx4j465xwqntbmu43nb2dzqwfvae"
  end

  test "from_data defaults to dag-cbor and accepts raw" do
    assert Cid.from_data(<<1>>).codec == 0x71
    assert Cid.from_data(<<1>>, Cid.raw()).codec == Cid.raw()

    assert 0x71 == 0x71
    assert Cid.raw() == 0x55
  end

  test "from_digest constroi o mesmo CID do from_data, com o padrao raw" do
    dados = "digest conhecido"

    assert Cid.from_digest(:crypto.hash(:sha256, dados)) == Cid.from_data(dados, Cid.raw())
  end

  test "round trips the binary form" do
    for codec <- [0x71, Cid.raw()] do
      cid = Cid.from_data(:crypto.strong_rand_bytes(32), codec)
      assert Cid.from_bytes(Cid.to_bytes(cid)) == cid
    end
  end

  test "round trips the string form" do
    cid = Cid.from_data(<<1, 2, 3>>, Cid.raw())

    assert Cid.parse(Cid.to_string(cid)) == cid
  end

  test "to_bytes is version, codec, multihash" do
    cid = Cid.from_data(<<1, 2, 3>>)

    assert Cid.to_bytes(cid) ==
             <<0x01, 0x71, 0x12, 0x20>> <> :crypto.hash(:sha256, <<1, 2, 3>>)
  end

  test "to_string is base32 lower with a b prefix" do
    assert String.starts_with?(Cid.to_string(Cid.from_data(<<1>>)), "b")
  end

  # parse/1 raises, and every one of these shapes made it raise. They come
  # from a query string or a record body, so the caller reading them must
  # not be the one to die.
  test "safe_parse answers :error on everything that makes parse raise" do
    for bad <- ["bafkrei", "b", "", "not a cid", "bafkre!", "bmfxxxxxxxx", "zzzz", nil, 42] do
      assert Cid.safe_parse(bad) == :error, inspect(bad)
    end
  end

  test "safe_parse answers :error on a non-base32 string and on a truncated cid" do
    assert Cid.safe_parse("bafyrei") == :error

    assert Cid.safe_parse(String.slice("bafyreiauu4dlrmesbnb7i24u7niyunmpxb6bg4dmpo7ul7wnslx5b77gf4", 0, 20)) == :error
  end

  test "safe_parse answers the same struct parse does on input that decodes" do
    cid = Cid.from_data(<<1, 2, 3>>, Cid.raw())

    assert Cid.safe_parse(Cid.to_string(cid)) == {:ok, cid}
  end

  # Parsing is not validating, and this is the shape that proves it: a CID
  # that decodes to a raw codec with no hash algorithm and an empty digest,
  # which parse/1 is perfectly happy to return. It is why callers that build
  # a path from a CID match on the struct instead of trusting the string.
  test "safe_parse is not validation: garbage that decodes comes back as a struct" do
    assert {:ok, cid} = Cid.safe_parse("bafkqaaa")
    assert cid.codec == Cid.raw()
    assert cid.hash_algo == 0
    assert cid.digest == ""

    assert {:ok, dag_cbor} =
             Cid.safe_parse("bafyreidykglsfhoixmivffc5uwhcgshx4j465xwqntbmu43nb2dzqwfvae")

    assert dag_cbor.codec == 0x71
  end
end
