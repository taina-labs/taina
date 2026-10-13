defmodule Taina.Repo.Migrations.CreateMaracaSchema do
  use Ecto.Migration

  # Porta para SQLite: tabelas planas (sem schema `maraca`), sem RLS DDL.
  # `username` nasce nullable porque o SQLite nao tem ALTER COLUMN DROP NOT
  # NULL (ver 20260610120000_allow_pending_invite_username): o estado final
  # (nullable, escolha de nome no aceite do convite) fica compactado aqui.
  def change do
    create table(:tekoas) do
      add :name, :string, null: false
      add :public_id, :string
      add :settings, :map, default: %{}
      add :storage_quota_bytes, :bigint
      add :storage_used_bytes, :bigint

      timestamps()
    end

    create unique_index(:tekoas, [:name])
    create unique_index(:tekoas, [:public_id])

    create table(:avas) do
      add :tekoa_id, references(:tekoas, on_delete: :delete_all), null: false
      add :username, :string
      add :email, :string, null: false
      add :confirmed_at, :utc_datetime_usec
      add :public_id, :string
      add :role, :string
      add :password_hash, :string
      add :email_confirmation_token_hash, :string
      add :email_confirmation_sent_at, :utc_datetime_usec
      add :reset_token_hash, :string
      add :reset_token_sent_at, :utc_datetime_usec
      add :invited_by_id, references(:avas, on_delete: :nilify_all)
      add :invited_at, :utc_datetime_usec

      timestamps()
    end

    create index(:avas, [:tekoa_id])
    create index(:avas, [:invited_by_id])

    create unique_index(:avas, [:email_confirmation_token_hash])

    create unique_index(:avas, [:reset_token_hash], where: "reset_token_hash IS NOT NULL")

    create unique_index(:avas, [:tekoa_id, :email], name: :avas_tekoa_id_email_index)

    create unique_index(:avas, [:tekoa_id, :username], name: :avas_tekoa_id_username_index)

    create unique_index(:avas, [:public_id])

    create table(:permissions) do
      add :resource_type, :string, null: false
      add :resource_id, :string, null: false
      add :action, :string, null: false
      add :ava_id, references(:avas, on_delete: :delete_all), null: false

      # O SQLite nao tem ON DELETE SET NULL (coluna); para FK de coluna unica,
      # SET NULL na linha equivale ao nilify de `granted_by_id`.
      add :granted_by_id, references(:avas, on_delete: :nilify_all)

      add :tekoa_id, references(:tekoas, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:permissions, [:tekoa_id])

    create unique_index(:permissions, [:ava_id, :resource_type, :resource_id, :action],
             name: "permissions_unique_grant"
           )

    create table(:access_requests) do
      add :resource_type, :string
      add :resource_id, :string
      add :reason, :text
      add :status, :string
      add :requester_id, references(:avas, on_delete: :delete_all), null: false
      add :owner_id, references(:avas, on_delete: :delete_all), null: false
      add :tekoa_id, references(:tekoas, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:access_requests, [:tekoa_id])
  end
end
