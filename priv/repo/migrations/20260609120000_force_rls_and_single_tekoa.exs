defmodule Taina.Repo.Migrations.ForceRlsAndSingleTekoa do
  @moduledoc """
  Impoe o modo single-tekoa (RFC 002, D2).

  A parte de `FORCE ROW LEVEL SECURITY` era do Postgres e nao tem equivalente
  no SQLite (sem RLS). O que fica portado e o indice unico sobre a expressao
  constante `(true)`, que garante no banco que so existe uma Tekoa por
  instancia. Sera removido no futuro modo de hospedagem gerenciada
  multi-tenant.
  """

  use Ecto.Migration

  def up do
    execute "CREATE UNIQUE INDEX single_tekoa_enforcement ON tekoas((true))"
  end

  def down do
    execute "DROP INDEX IF EXISTS single_tekoa_enforcement"
  end
end
