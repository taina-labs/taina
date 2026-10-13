defmodule Taina.Repo.Migrations.AddZonaToYbira do
  use Ecto.Migration

  # Duas zonas (RFC_003 D1): coluna que decide a privacidade do item.
  # Ordem deliberada: cria a coluna com default 'casa' (arquivos novos nascem
  # privados), depois faz backfill do acervo existente para 'praca'. Inverter
  # isso (default casa sem backfill) privatizaria silenciosamente o que hoje e
  # comum. O CHECK casa o enum da aplicacao no nivel do banco. O SQLite nao
  # tem ALTER TABLE ADD CONSTRAINT, mas aceita CHECK no ADD COLUMN quando ele
  # so referencia a coluna nova, entao a restricao entra junto.
  def up do
    alter table(:files) do
      add :zona, :string,
        null: false,
        default: "casa",
        check: %{name: "files_zona_check", expr: "zona IN ('casa','praca')"}
    end

    alter table(:folders) do
      add :zona, :string,
        null: false,
        default: "casa",
        check: %{name: "folders_zona_check", expr: "zona IN ('casa','praca')"}
    end

    # Backfill: tudo que ja existe no momento da migracao e o acervo = praca.
    execute "UPDATE files SET zona = 'praca'"
    execute "UPDATE folders SET zona = 'praca'"
  end

  def down do
    alter table(:files) do
      remove :zona
    end

    alter table(:folders) do
      remove :zona
    end
  end
end
