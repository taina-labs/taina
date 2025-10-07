defmodule Taina.Repo.Migrations.CreateGuaraSchema do
  use Ecto.Migration

  def change do
    execute "CREATE SCHEMA IF NOT EXISTS guara", "DROP SCHEMA IF EXISTS guara CASCADE"

    create table(:chats, prefix: "guara") do
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :created_by_id, references(:avas, on_delete: :restrict, prefix: "maraca"), null: false
      add :name, :string
      add :icon, :string
      add :public_id, :string

      timestamps()
    end

    create index(:chats, [:tekoa_id], prefix: "guara")
    create index(:chats, [:created_by_id], prefix: "guara")
    create unique_index(:chats, [:public_id], prefix: "guara")

    create table(:participants, prefix: "guara", primary_key: false) do
      add :chat_id, references(:chats, on_delete: :delete_all, prefix: "guara"),
        null: false,
        primary_key: true

      add :ava_id, references(:avas, on_delete: :delete_all, prefix: "maraca"),
        null: false,
        primary_key: true

      add :joined_at, :utc_datetime_usec, null: false
      add :last_read_at, :utc_datetime_usec
      add :role, :string, default: "member"

      timestamps()
    end

    create index(:participants, [:chat_id], prefix: "guara")
    create index(:participants, [:ava_id], prefix: "guara")

    create table(:messages, prefix: "guara") do
      add :chat_id, references(:chats, on_delete: :delete_all, prefix: "guara"), null: false
      add :sender_id, references(:avas, on_delete: :restrict, prefix: "maraca"), null: false
      add :parent_id, references(:messages, on_delete: :nilify_all, prefix: "guara")
      add :file_id, references(:files, on_delete: :nilify_all, prefix: "ybira")
      add :content, :text
      add :message_type, :string, default: "text"
      add :metadata, :map, default: %{}
      add :public_id, :string

      timestamps()
    end

    create index(:messages, [:chat_id, {:desc, "inserted_at"}], prefix: "guara")
    create index(:messages, [:sender_id], prefix: "guara")
    create index(:messages, [:parent_id], prefix: "guara")
    create index(:messages, [:file_id], prefix: "guara")
    create unique_index(:messages, [:public_id], prefix: "guara")

    execute "ALTER TABLE guara.chats ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE guara.participants ENABLE ROW LEVEL SECURITY"
    execute "ALTER TABLE guara.messages ENABLE ROW LEVEL SECURITY"
  end
end
