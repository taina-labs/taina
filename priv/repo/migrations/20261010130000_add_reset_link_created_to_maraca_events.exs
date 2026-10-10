defmodule Taina.Repo.Migrations.AddResetLinkCreatedToMaracaEvents do
  use Ecto.Migration

  # O reset de senha mediado pelo zelador entra no mural (RFC_003 seção 6,
  # camada 1): `reset_link_created`, um ato sobre a máquina, não sobre dados.
  # O ledger é append-only (linhas nunca mudam), então só recriamos o CHECK do
  # vocabulário; o enum da aplicação (`Taina.Maraca.Event`) e o CHECK do banco
  # casam como na criação da tabela.
  def up do
    execute "ALTER TABLE maraca.events DROP CONSTRAINT events_type_check"

    execute """
    ALTER TABLE maraca.events ADD CONSTRAINT events_type_check CHECK (type IN ('invite_created','invite_accepted','member_deactivated','member_role_changed','member_reactivated','reset_link_created','published_to_praca','moved_between_zones','access_requested','access_granted','access_denied','quota_changed'))
    """
  end

  def down do
    execute "ALTER TABLE maraca.events DROP CONSTRAINT events_type_check"

    execute """
    ALTER TABLE maraca.events ADD CONSTRAINT events_type_check CHECK (type IN ('invite_created','invite_accepted','member_deactivated','member_role_changed','member_reactivated','published_to_praca','moved_between_zones','access_requested','access_granted','access_denied','quota_changed'))
    """
  end
end
