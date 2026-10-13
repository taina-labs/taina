defmodule Taina.Repo.Migrations.AddInviteRevokedToMaracaEvents do
  use Ecto.Migration

  # Revogar um convite pendente é um ato do zelador (RFC_003 seção 6). Porta
  # SQLite: o CHECK do vocabulário nasce completo na criação da tabela
  # (20261005120000), porque o SQLite não tem ALTER TABLE ADD/DROP CONSTRAINT.
  def up, do: :ok

  def down, do: :ok
end
