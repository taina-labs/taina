defmodule Ypy.TidTest do
  use ExUnit.Case, async: true

  import Bitwise

  alias Ypy.Tid

  @alphabet ~c"234567abcdefghijklmnopqrstuvwxyz"

  test "encodes exactly 13 characters from the base32-sortable alphabet" do
    tid = Tid.encode(1)

    assert String.length(tid) == 13
    assert tid |> String.to_charlist() |> Enum.all?(&(&1 in @alphabet))
  end

  test "round trips through the alphabet" do
    for n <- [0, 1, 2, 31, 32, 1234, 1_000_000_000, 4_000_000_000_000_000] do
      assert decode(Tid.encode(n)) == n
    end
  end

  test "encoded strings sort in the same order as the integers" do
    ints = Enum.sort([9, 100, 3, 77_777, 1, 5_000_000, 42])

    encoded = Enum.map(ints, &Tid.encode/1)

    assert encoded == Enum.sort(encoded)
  end

  test "next/3 returns a value strictly greater than last" do
    {tid, n} = Tid.next(0, 1_700_000_000_000_000, 7)

    assert n > 0
    assert tid == Tid.encode(n)
  end

  test "next/3 increases strictly within the same microsecond when the caller threads the last value" do
    micros = 1_700_000_000_000_000
    {_tid1, n1} = Tid.next(1_000, micros, 5)
    {_tid2, n2} = Tid.next(n1, micros, 5)

    assert n2 > n1
    assert n1 >= 1_000 + 1
  end

  test "next/3 keeps the clock id in the low 10 bits" do
    micros = 1_700_000_000_000_000

    for clock_id <- [0, 1, 512, 1023] do
      {_tid, n} = Tid.next(10_000_000_000_000, micros, clock_id)

      assert n >= micros <<< 10
      assert (n &&& 0x3FF) == clock_id
    end
  end

  test "next/3 moves past last when the timestamp is behind it" do
    {_tid, n} = Tid.next(1 <<< 62, 1, 1023)

    assert n == (1 <<< 62) + 1
  end

  defp decode(tid) do
    tid
    |> String.to_charlist()
    |> Enum.reduce(0, fn c, acc -> acc * 32 + Enum.find_index(@alphabet, &(&1 == c)) end)
  end
end
