defmodule Taina.Repo.Migrations.AddResetLinkCreatedToMaracaEvents do
  use Ecto.Migration

  # O reset de senha mediado pelo zelador entra no mural (RFC_003 seção 6,
  # camada 1). Porta SQLite: o CHECK do vocabulário nasce completo na criação
  # da tabela (20261005120000), porque o SQLite não tem ALTER TABLE
  # ADD/DROP CONSTRAINT.
  def up, do: :ok

  def down, do: :ok
end
