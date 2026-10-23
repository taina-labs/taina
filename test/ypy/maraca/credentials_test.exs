defmodule Ypy.Maraca.CredentialsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Ypy.Maraca.Credentials

  @rounds [log_rounds: 4]

  test "hash produces a bcrypt hash that verifies the password" do
    hash = Credentials.hash("segredo da comunidade", @rounds)

    assert String.starts_with?(hash, "$2")
    assert Credentials.valid_password?("segredo da comunidade", hash)
    refute Credentials.valid_password?("outro segredo", hash)
  end

  test "the default rounds are the bcrypt_elixir ones" do
    assert String.starts_with?(Credentials.hash("segredo"), "$2b$04$")
  end

  test "a malformed stored hash answers false instead of crashing" do
    refute Credentials.valid_password?("segredo", "nao-e-um-hash")
  end

  property "any binary password roundtrips through hash and verify" do
    check all(
            password <- StreamData.binary(min_length: 1, max_length: 60),
            max_runs: 20
          ) do
      assert Credentials.valid_password?(password, Credentials.hash(password, @rounds))
    end
  end
end
