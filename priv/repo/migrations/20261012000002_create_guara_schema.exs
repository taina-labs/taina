defmodule Taina.Repo.Migrations.CreateGuaraSchema do
  use Ecto.Migration

  # Porta para SQLite: tabelas planas (sem schema `guara`), sem RLS DDL.
  # As FKs apontam para as tabelas do kernel Ypy (`maraca_tekoas`,
  # `maraca_avas`, `ybira_files`), que as owns agora.
  def change do
    create table(:chats) do
      add :tekoa_id, references(:maraca_tekoas, on_delete: :delete_all), null: false
      add :created_by_id, references(:maraca_avas, on_delete: :restrict), null: false
      add :name, :string
      add :icon, :string
      add :public_id, :string

      timestamps()
    end

    create index(:chats, [:tekoa_id])
    create index(:chats, [:created_by_id])
    create unique_index(:chats, [:public_id])

    create table(:participants, primary_key: false) do
      add :chat_id, references(:chats, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :ava_id, references(:maraca_avas, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :joined_at, :utc_datetime_usec, null: false
      add :last_read_at, :utc_datetime_usec
      add :role, :string, default: "member"

      timestamps()
    end

    create table(:messages) do
      add :chat_id, references(:chats, on_delete: :delete_all), null: false
      add :sender_id, references(:maraca_avas, on_delete: :restrict), null: false
      add :parent_id, references(:messages, on_delete: :nilify_all)
      add :file_id, references(:ybira_files, on_delete: :nilify_all)
      add :content, :text
      add :message_type, :string, default: "text"
      add :metadata, :map, default: %{}
      add :public_id, :string

      timestamps()
    end

    execute "CREATE INDEX messages_chat_id_inserted_at_index ON messages (chat_id, inserted_at DESC, id DESC)"

    create index(:messages, [:sender_id])
    create index(:messages, [:parent_id])
    create index(:messages, [:file_id])
    create unique_index(:messages, [:public_id])
  end
end
