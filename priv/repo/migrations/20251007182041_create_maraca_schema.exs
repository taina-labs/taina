defmodule Taina.Repo.Migrations.CreateMaracaSchema do
  use Ecto.Migration

  def change do
    execute "CREATE SCHEMA IF NOT EXISTS maraca", "DROP SCHEMA IF EXISTS maraca CASCADE"

    create table(:tekoas, prefix: "maraca") do
      add :name, :string, null: false
      add :public_id, :string
      add :settings, :map, default: %{}
      add :storage_quota_bytes, :bigint
      add :storage_used_bytes, :bigint

      timestamps()
    end

    create unique_index(:tekoas, [:name], prefix: "maraca")
    create unique_index(:tekoas, [:public_id], prefix: "maraca")

    create table(:avas, prefix: "maraca") do
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :username, :string, null: false
      add :email, :string, null: false
      add :confirmed_at, :utc_datetime_usec
      add :public_id, :string
      add :role, :string
      add :password_hash, :string
      add :email_confirmation_token, :string
      add :email_confirmation_sent_at, :utc_datetime_usec

      timestamps()
    end

    create index(:avas, [:tekoa_id], prefix: "maraca")

    create unique_index(:avas, [:email_confirmation_token], prefix: "maraca")

    create unique_index(:avas, [:tekoa_id, :email],
             prefix: "maraca",
             name: :avas_tekoa_id_email_index
           )

    create unique_index(:avas, [:tekoa_id, :username],
             prefix: "maraca",
             name: :avas_tekoa_id_username_index
           )

    create unique_index(:avas, [:public_id], prefix: "maraca")

    create table(:permissions, prefix: "maraca") do
      add :resource_type, :string
      add :resource_id, :string
      add :action, :string
      add :ava_id, references(:avas, on_delete: :delete_all, prefix: "maraca"), null: false

      add :granted_by_id,
          references(:avas, on_delete: {:nilify, [:granted_by_id]}, prefix: "maraca")

      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false

      timestamps()
    end

    create unique_index(:permissions, [:ava_id, :resource_type, :resource_id, :action],
             prefix: "maraca",
             name: "permissions_unique_grant"
           )

    create table(:access_requests, prefix: "maraca") do
      add :resource_type, :string
      add :resource_id, :string
      add :reason, :text
      add :status, :string
      add :requester_id, references(:avas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :owner_id, references(:avas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false

      timestamps()
    end

    execute "ALTER TABLE maraca.tekoas ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE maraca.avas ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE maraca.permissions ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE maraca.access_requests ENABLE ROW LEVEL SECURITY"
  end
end
