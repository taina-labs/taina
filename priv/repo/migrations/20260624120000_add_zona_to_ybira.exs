defmodule Taina.Repo.Migrations.AddZonaToYbira do
  use Ecto.Migration

  # Duas zonas (RFC_003 D1): coluna que decide a privacidade do item.
  # Ordem deliberada: cria a coluna com default 'casa' (arquivos novos nascem
  # privados), depois faz backfill do acervo existente para 'praca'. Inverter
  # isso (default casa sem backfill) privatizaria silenciosamente o que hoje e
  # comum. O CHECK casa o enum da aplicacao no nivel do banco.
  def up do
    alter table(:files, prefix: "ybira") do
      add :zona, :string, null: false, default: "casa"
    end

    alter table(:folders, prefix: "ybira") do
      add :zona, :string, null: false, default: "casa"
    end

    execute "ALTER TABLE ybira.files ADD CONSTRAINT files_zona_check CHECK (zona IN ('casa','praca'))"

    execute "ALTER TABLE ybira.folders ADD CONSTRAINT folders_zona_check CHECK (zona IN ('casa','praca'))"

    # Backfill: tudo que ja existe no momento da migracao e o acervo = praca.
    execute "UPDATE ybira.files SET zona = 'praca'"
    execute "UPDATE ybira.folders SET zona = 'praca'"
  end

  def down do
    execute "ALTER TABLE ybira.files DROP CONSTRAINT IF EXISTS files_zona_check"
    execute "ALTER TABLE ybira.folders DROP CONSTRAINT IF EXISTS folders_zona_check"

    alter table(:files, prefix: "ybira") do
      remove :zona
    end

    alter table(:folders, prefix: "ybira") do
      remove :zona
    end
  end
end
