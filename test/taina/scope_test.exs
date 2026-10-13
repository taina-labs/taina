defmodule Taina.ScopeTest do
  @moduledoc """
  Contrato do `Scope.for_ava/1`: exige a Tekoa pré-carregada e, sem ela, levanta
  um erro que aponta o preload em vez de um `FunctionClauseError` sem pista.

  Sem banco: `for_ava/1` é casamento de padrões puro, structs bastam.
  """
  use ExUnit.Case, async: true

  alias Ecto.Association.NotLoaded
  alias Taina.Scope
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa

  test "for_ava/1 builds a scope when the Tekoa is preloaded" do
    ava = %Ava{tekoa: %Tekoa{}}

    assert %Ypy.Scope{ava: ^ava, tekoa: %Tekoa{}} = Scope.for_ava(ava)
  end

  test "for_ava/1 raises a clear error when the Tekoa is not preloaded" do
    ava = %Ava{tekoa: %NotLoaded{}}

    assert_raise ArgumentError, ~r/pré-carregada/, fn ->
      Scope.for_ava(ava)
    end
  end
end
