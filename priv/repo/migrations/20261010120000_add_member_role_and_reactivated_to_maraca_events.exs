defmodule Taina.Repo.Migrations.AddMemberRoleAndReactivatedToMaracaEvents do
  use Ecto.Migration

  # Atos do zelador sobre papéis entram no mural (RFC_003 seção 6, camada 1):
  # `member_role_changed` e `member_reactivated`. O ledger é append-only (linhas
  # nunca mudam), então só recriamos o CHECK do vocabulário; o enum da aplicação
  # (`Taina.Maraca.Event`) e o CHECK do banco casam como na criação da tabela.
  def up do
    execute "ALTER TABLE maraca.events DROP CONSTRAINT events_type_check"

    execute """
    ALTER TABLE maraca.events ADD CONSTRAINT events_type_check CHECK (type IN ('invite_created','invite_accepted','member_deactivated','member_role_changed','member_reactivated','published_to_praca','moved_between_zones','access_requested','access_granted','access_denied','quota_changed'))
    """
  end

  def down do
    execute "ALTER TABLE maraca.events DROP CONSTRAINT events_type_check"

    execute """
    ALTER TABLE maraca.events ADD CONSTRAINT events_type_check CHECK (type IN ('invite_created','invite_accepted','member_deactivated','published_to_praca','moved_between_zones','access_requested','access_granted','access_denied','quota_changed'))
    """
  end
end
