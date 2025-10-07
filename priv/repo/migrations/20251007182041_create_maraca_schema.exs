defmodule Taina.Repo.Migrations.CreateMaracaSchema do
  use Ecto.Migration

  def change do
    execute "CREATE SCHEMA IF NOT EXISTS maraca", "DROP SCHEMA IF EXISTS maraca CASCADE"
    execute "ALTER TABLE maraca.tekoas ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE maraca.avas ENABLE ROW LEVEL SECURITY"

    create table(:tekoas, prefix: "maraca") do
      add :name, :string, null: false
      add :public_id, :string
      add :settings, :map, default: %{}
      add :storage_quota_gb, :integer, default: 100
      add :storage_used_bytes, :bigint, default: 0

      timestamps()
    end

    create unique_index(:tekoas, [:name], prefix: "maraca")
    create unique_index(:tekoas, [:public_id], prefix: "maraca")

    create table(:avas, prefix: "maraca") do
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :username, :string, null: false
      add :email, :string, null: false
      add :confirmed_at, :naive_datetime
      add :public_id, :string
      add :role, :string, default: "member"

      timestamps()
    end

    create index(:avas, [:tekoa_id], prefix: "maraca")

    create unique_index(:avas, [:tekoa_id, :email],
             prefix: "maraca",
             name: :avas_tekoa_id_email_index
           )

    create unique_index(:avas, [:tekoa_id, :username],
             prefix: "maraca",
             name: :avas_tekoa_id_username_index
           )

    create unique_index(:avas, [:public_id], prefix: "maraca")
  end
end
