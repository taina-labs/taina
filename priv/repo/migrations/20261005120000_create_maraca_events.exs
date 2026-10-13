defmodule Taina.Repo.Migrations.CreateMaracaEvents do
  use Ecto.Migration

  # Mural (RFC_003 seção 6, camada 1): livro-caixa append-only do que aconteceu
  # na comunidade, "quem fez o quê". Só `inserted_at`: registro é consequência
  # do ato, nunca é editado nem apagado, `updated_at` seria o sinal errado
  # (mesma leitura do zona: o CHECK casa o enum da aplicação no nível do banco).
  #
  # Porta SQLite: sem RLS DDL, e o CHECK do vocabulário já nasce com a lista
  # final de tipos. O SQLite nao tem ALTER TABLE ADD/DROP CONSTRAINT, entao as
  # tres migrações seguintes que ampliavam o CHECK (20261010120000,
  # 20261010130000, 20261011150000) viram no-op; em cadeia nova o estado
  # intermediario nao e observavel.
  @event_types ~w(invite_created invite_accepted invite_revoked member_deactivated member_role_changed member_reactivated reset_link_created published_to_praca moved_between_zones access_requested access_granted access_denied quota_changed)

  def up do
    create table(:events) do
      add :tekoa_id, references(:tekoas, on_delete: :delete_all), null: false

      # Nullable: atos do sistema (futuro) não têm autor morador.
      add :ava_id, references(:avas, on_delete: :nilify_all)

      add :type, :string,
        null: false,
        check: %{
          name: "events_type_check",
          expr: "type IN (#{Enum.map_join(@event_types, ",", &"'#{&1}'")})"
        }

      add :payload, :map, null: false, default: %{}
      add :public_id, :string

      timestamps(updated_at: false)
    end

    create unique_index(:events, [:public_id])

    execute "CREATE INDEX events_tekoa_id_inserted_at_index ON events (tekoa_id, inserted_at DESC)"

    # O ledger e dado de Tekoa como qualquer outro: no Postgres ele tinha
    # policy RLS propria; no SQLite o isolamento e aplicado pela camada de
    # aplicacao (Taina.Repo.with_tekoa/2).
  end

  def down do
    drop table(:events)
  end
end
