defmodule Taina.Repo.Migrations.CreateGuaraSchema do
  use Ecto.Migration

  def change do
    # Criar schema guara
    execute "CREATE SCHEMA IF NOT EXISTS guara", "DROP SCHEMA IF EXISTS guara CASCADE"

    # Tabela de chats (sem distinção entre DM e grupo!)
    create table(:chats, prefix: "guara", primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :created_by_id, references(:avas, on_delete: :restrict, prefix: "maraca"), null: false
      add :name, :string
      add :icon, :string
      add :public_id, :string

      timestamps()
    end

    # Índices para Chats
    create index(:chats, [:tekoa_id], prefix: "guara")
    create index(:chats, [:created_by_id], prefix: "guara")
    create unique_index(:chats, [:public_id], prefix: "guara")

    # Tabela de participantes (join table com informações extras)
    create table(:participants, prefix: "guara", primary_key: false) do
      add :chat_id, references(:chats, on_delete: :delete_all, prefix: "guara"),
        null: false,
        primary_key: true

      add :ava_id, references(:avas, on_delete: :delete_all, prefix: "maraca"),
        null: false,
        primary_key: true

      add :joined_at, :naive_datetime, null: false
      add :last_read_at, :naive_datetime
      add :role, :string, default: "member"

      timestamps()
    end

    # Índices para Participants
    create index(:participants, [:chat_id], prefix: "guara")
    create index(:participants, [:ava_id], prefix: "guara")

    create unique_index(:participants, [:chat_id, :ava_id],
             prefix: "guara",
             name: :participants_chat_id_ava_id_index
           )

    # Tabela de mensagens
    create table(:messages, prefix: "guara", primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :chat_id, references(:chats, on_delete: :delete_all, prefix: "guara"), null: false
      add :sender_id, references(:avas, on_delete: :restrict, prefix: "maraca"), null: false
      add :parent_id, references(:messages, on_delete: :set_null, prefix: "guara")
      add :file_id, references(:files, on_delete: :set_null, prefix: "ybira")
      add :content, :text
      add :message_type, :string, default: "text"
      add :metadata, :map, default: %{}
      add :public_id, :string

      timestamps()
    end

    # Índices para Messages (CRÍTICO para performance!)
    create index(:messages, [:chat_id, :created_at], prefix: "guara", order: [desc: :created_at])
    create index(:messages, [:sender_id], prefix: "guara")
    create index(:messages, [:parent_id], prefix: "guara")
    create index(:messages, [:file_id], prefix: "guara")
    create unique_index(:messages, [:public_id], prefix: "guara")

    # Constraint: mensagem deve ter conteúdo OU arquivo
    create constraint(:messages, :must_have_content_or_file,
             prefix: "guara",
             check: "(content IS NOT NULL AND content != '') OR file_id IS NOT NULL"
           )
  end
end
