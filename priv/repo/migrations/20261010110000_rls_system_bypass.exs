defmodule Taina.Repo.Migrations.RlsSystemBypass do
  @moduledoc """
  No Postgres, este módulo dava às políticas RLS uma válvula de sistema
  (`app.bypass_rls`) para consultas de sistema rodarem no papel restrito de
  produção.

  O SQLite não tem Row-Level Security e a válvula não existe: operações de
  sistema rodam fora de contexto com `skip_tekoa_id: true` /
  `Taina.Repo.with_system/1`, e o guard `prepare_query/3` é a única fronteira.
  A migração fica no histórico só para casar a cadeia de versões com a do
  Postgres; não executa nada.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
