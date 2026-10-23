defmodule Ypy.Assembleia.PolicyTest do
  use ExUnit.Case, async: true

  alias Ypy.Assembleia.Policy

  test "quorum is ceil(moradores/2)" do
    for {moradores, esperado} <- [
          {0, 0},
          {1, 1},
          {2, 1},
          {3, 2},
          {4, 2},
          {5, 3},
          {6, 3},
          {7, 4},
          {8, 4}
        ] do
      assert Policy.quorum(moradores) == esperado
    end
  end

  test "tally passes with quorum and a simple majority" do
    assert Policy.tally([:sim, :sim, :nao], 5) == :aprovada
    assert Policy.tally([:sim, :sim, :nao], 4) == :aprovada
  end

  test "tally rejects a tie and a nao majority" do
    assert Policy.tally([:sim, :nao], 4) == :rejeitada
    assert Policy.tally([:sim, :nao, :nao], 5) == :rejeitada
    assert Policy.tally([:nao, :nao], 4) == :rejeitada
  end

  test "tally expires when the quorum is missed, even with every vote a sim" do
    assert Policy.tally([:sim, :sim], 5) == :expirada
    assert Policy.tally([:sim], 7) == :expirada
    assert Policy.tally([], 5) == :expirada
  end

  test "a choice that is neither sim nor nao is not a vote" do
    assert Policy.tally([:sim, :maybe], 2) == :aprovada
    assert Policy.tally([:maybe], 2) == :expirada
  end

  test "expiry passes exactly at the turn of the deadline" do
    fecha = DateTime.from_naive!(~N[2026-06-01 10:00:00], "Etc/UTC")

    refute Policy.expired?(fecha, DateTime.shift(fecha, second: -1))
    refute Policy.expired?(fecha, fecha)
    assert Policy.expired?(fecha, DateTime.shift(fecha, second: 1))
  end
end
