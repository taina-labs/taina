defmodule Taina.Repo.Migrations.SingleTekoaBox do
  @moduledoc """
  A trava de uma-Tekoa-por-box (RFC 002 D2): politica do box, nao invariante
  do kernel (RFC_006 D11). O indice unico sobre a expressao constante `(true)`
  garante no banco que so existe uma Tekoa por instancia.
  """

  use Ecto.Migration

  def up do
    execute "CREATE UNIQUE INDEX single_tekoa_enforcement ON maraca_tekoas((true))"
  end

  def down do
    execute "DROP INDEX IF EXISTS single_tekoa_enforcement"
  end
end
