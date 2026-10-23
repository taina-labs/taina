defmodule Ypy.MuralTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Bitwise

  alias Ypy.Cbor
  alias Ypy.Mural
  alias Ypy.Secp256k1

  setup do
    {pub, priv} = Secp256k1.generate_keypair()
    {:ok, pub: pub, priv: priv}
  end

  defp seal_chain(priv, payloads) do
    {entries, _last_cid, _last_seq} =
      Enum.reduce(payloads, {[], nil, 1}, fn payload, {acc, prev, seq} ->
        entry = Mural.seal(seq, prev, payload, priv)
        {[entry | acc], Mural.entry_cid(entry), seq + 1}
      end)

    Enum.reverse(entries)
  end

  test "a chain of N verifies", %{priv: priv, pub: pub} do
    payloads =
      Enum.map(1..5, fn i -> %{"kind" => "publish", "rkey" => "rkey-#{i}", "seq_do_ato" => i} end)

    chain = seal_chain(priv, payloads)

    assert Mural.verify_chain(pub, chain) == :ok
    assert Mural.verify_chain(pub, []) == :ok
  end

  property "a chain of any length verifies", %{priv: priv, pub: pub} do
    check all(n <- StreamData.integer(1..8)) do
      payloads =
        Enum.map(1..n, fn i -> %{"kind" => "invite", "para" => "morador-#{i}"} end)

      chain = seal_chain(priv, payloads)

      assert Mural.verify_chain(pub, chain) == :ok
    end
  end

  property "flipping any payload byte breaks the chain at exactly that entry", %{
    priv: priv,
    pub: pub
  } do
    check all(
            n <- StreamData.integer(2..6),
            at <- StreamData.integer(0..(n - 1))
          ) do
      chain =
        seal_chain(priv, Enum.map(1..n, &%{"kind" => "ato", "n" => &1, "data" => "0123456789"}))

      corrompida =
        List.update_at(chain, at, fn entry ->
          put_in(entry, ["payload", "data"], flip_bit(entry["payload"]["data"]))
        end)

      assert Mural.verify_chain(pub, corrompida) == {:error, {at, :bad_signature}}
    end
  end

  property "flipping a seq breaks the chain at exactly that entry", %{priv: priv, pub: pub} do
    check all(
            n <- StreamData.integer(2..6),
            at <- StreamData.integer(0..(n - 1))
          ) do
      chain = seal_chain(priv, Enum.map(1..n, &%{"kind" => "ato", "n" => &1}))

      corrompida =
        List.update_at(chain, at, fn entry -> Map.put(entry, "seq", entry["seq"] + 99) end)

      assert Mural.verify_chain(pub, corrompida) == {:error, {at, :bad_seq}}
    end
  end

  test "a broken link breaks at exactly that entry", %{priv: priv, pub: pub} do
    chain = seal_chain(priv, [%{"n" => 1}, %{"n" => 2}, %{"n" => 3}])

    at = 2

    corrompida =
      List.update_at(chain, at, fn entry -> Map.put(entry, "prev", Ypy.Cid.from_data("outro")) end)

    assert Mural.verify_chain(pub, corrompida) == {:error, {at, :bad_link}}
  end

  test "a chain signed by another key does not verify with this one", %{priv: priv} do
    {outra_pub, _outra_priv} = Secp256k1.generate_keypair()

    chain = seal_chain(priv, [%{"n" => 1}, %{"n" => 2}])

    assert Mural.verify_chain(outra_pub, chain) == {:error, {0, :bad_signature}}
  end

  test "reordered entries break at the first one that is out of place", %{priv: priv, pub: pub} do
    chain = seal_chain(priv, [%{"n" => 1}, %{"n" => 2}, %{"n" => 3}])

    assert Mural.verify_chain(pub, Enum.reverse(chain)) == {:error, {0, :bad_seq}}
  end

  test "an entry missing a field is a bad entry, not a crash", %{priv: priv, pub: pub} do
    chain = seal_chain(priv, [%{"n" => 1}])
    sem_assinatura = Enum.map(chain, &Map.delete(&1, "signature"))

    assert Mural.verify_chain(pub, sem_assinatura) == {:error, {0, :bad_entry}}
  end

  test "encode_entry/1 round trips through the decoder and entry_cid/1 is stable" do
    {_pub, priv} = Secp256k1.generate_keypair()
    entry = Mural.seal(1, nil, %{"n" => 1}, priv)

    decoded = Cbor.decode!(Mural.encode_entry(entry))
    assert decoded["seq"] == entry["seq"]
    assert decoded["prev"] == entry["prev"]
    assert decoded["payload"] == entry["payload"]
    assert %Ypy.Cbor.Bytes{data: signature} = decoded["signature"]
    assert signature == entry["signature"]

    assert Mural.entry_cid(entry) == Mural.entry_cid(entry)
    assert Mural.entry_cid(entry) != Mural.entry_cid(Mural.seal(1, nil, %{"n" => 2}, priv))
  end

  defp flip_bit(bin) do
    i = :rand.uniform(byte_size(bin)) - 1
    <<pre::binary-size(^i), b, rest::binary>> = bin
    <<pre::binary, bxor(b, 1), rest::binary>>
  end
end
