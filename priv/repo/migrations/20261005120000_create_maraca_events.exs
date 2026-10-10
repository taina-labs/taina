defmodule Taina.Repo.Migrations.CreateMaracaEvents do
  use Ecto.Migration

  # Mural (RFC_003 seção 6, camada 1): livro-caixa append-only do que aconteceu
  # na comunidade, "quem fez o quê". Só `inserted_at`: registro é consequência
  # do ato, nunca é editado nem apagado, `updated_at` seria o sinal errado
  # (mesma leitura do zona: o CHECK casa o enum da aplicação no nível do banco).
  def up do
    create table(:events, prefix: "maraca") do
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false

      # Nullable: atos do sistema (futuro) não têm autor morador.
      add :ava_id, references(:avas, on_delete: :nilify_all, prefix: "maraca")

      add :type, :string, null: false
      add :payload, :map, null: false, default: %{}
      add :public_id, :string

      timestamps(updated_at: false)
    end

    create unique_index(:events, [:public_id], prefix: "maraca")
    create index(:events, [:tekoa_id, {:desc, :inserted_at}], prefix: "maraca")

    execute """
    ALTER TABLE maraca.events ADD CONSTRAINT events_type_check CHECK (type IN ('invite_created','invite_accepted','member_deactivated','published_to_praca','moved_between_zones','access_requested','access_granted','access_denied','quota_changed'))
    """

    execute "ALTER TABLE maraca.events ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE maraca.events FORCE ROW LEVEL SECURITY"

    execute """
    CREATE POLICY event_isolation ON maraca.events
      FOR ALL
      USING (
        tekoa_id IN (
          SELECT id FROM maraca.tekoas
          WHERE public_id = current_setting('app.current_tekoa_id', true)
        )
      )
    """
  end

  def down do
    execute "DROP POLICY IF EXISTS event_isolation ON maraca.events"
    execute "ALTER TABLE maraca.events NO FORCE ROW LEVEL SECURITY"
    execute "ALTER TABLE maraca.events DISABLE ROW LEVEL SECURITY"

    drop table(:events, prefix: "maraca")
  end
end
