defmodule Taina.AccountOperatorTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.AccountOperator

  test "reset_password returns not_found for an unknown username" do
    tekoa_fixture()

    assert {:error, :not_found} = AccountOperator.reset_password("nao-existe", "novasenha123")
  end
end
