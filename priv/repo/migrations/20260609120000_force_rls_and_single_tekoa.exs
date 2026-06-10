defmodule Taina.Repo.Migrations.ForceRlsAndSingleTekoa do
  @moduledoc """
  Liga o RLS de verdade e impõe o modo single-tekoa (RFC 002, D2).

  `ENABLE ROW LEVEL SECURITY` sozinho não aplica políticas ao dono das
  tabelas — e a aplicação conecta como dono. `FORCE ROW LEVEL SECURITY`
  fecha essa brecha. Atenção: superusers do PostgreSQL ainda ignoram RLS por
  definição; em produção a aplicação deve conectar com uma role que não seja
  superuser (o teste de isolamento em `test/taina/rls_isolation_test.exs`
  valida exatamente esse cenário).

  O índice único sobre a expressão constante `(true)` garante no banco que
  só existe uma Tekoa por instância. Será removido no futuro modo de
  hospedagem gerenciada multi-tenant.
  """

  use Ecto.Migration

  @rls_tables [
    "maraca.tekoas",
    "maraca.avas",
    "maraca.permissions",
    "maraca.access_requests",
    "ybira.folders",
    "ybira.files",
    "guara.chats",
    "guara.participants",
    "guara.messages"
  ]

  def up do
    for table <- @rls_tables do
      execute "ALTER TABLE #{table} FORCE ROW LEVEL SECURITY"
    end

    execute "CREATE UNIQUE INDEX single_tekoa_enforcement ON maraca.tekoas ((true))"
  end

  def down do
    execute "DROP INDEX IF EXISTS maraca.single_tekoa_enforcement"

    for table <- @rls_tables do
      execute "ALTER TABLE #{table} NO FORCE ROW LEVEL SECURITY"
    end
  end
end
