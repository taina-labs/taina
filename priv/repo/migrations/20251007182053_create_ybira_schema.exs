defmodule Taina.Repo.Migrations.CreateYbiraSchema do
  use Ecto.Migration

  def change do
    # Criar schema ybira
    execute "CREATE SCHEMA IF NOT EXISTS ybira", "DROP SCHEMA IF EXISTS ybira CASCADE"

    # Tabela de pastas
    create table(:folders, prefix: "ybira", primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :ava_id, references(:avas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :folder_id, references(:folders, on_delete: :delete_all, prefix: "ybira")
      add :name, :string, null: false
      add :public_id, :string

      timestamps()
    end

    # Índices para Folders
    create index(:folders, [:ava_id], prefix: "ybira")
    create index(:folders, [:tekoa_id], prefix: "ybira")
    create index(:folders, [:folder_id], prefix: "ybira", name: :folders_parent_id_index)
    create unique_index(:folders, [:public_id], prefix: "ybira")

    # Tabela de arquivos
    create table(:files, prefix: "ybira", primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :ava_id, references(:avas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :tekoa_id, references(:tekoas, on_delete: :delete_all, prefix: "maraca"), null: false
      add :folder_id, references(:folders, on_delete: :set_null, prefix: "ybira")
      add :filename, :string, null: false
      add :original_filename, :string, null: false
      add :filepath, :string, null: false
      add :mime_type, :string, null: false
      add :file_size_bytes, :bigint, null: false
      add :file_hash, :string
      add :metadata, :map, default: %{}
      add :public_id, :string
      add :deleted_at, :naive_datetime

      timestamps()
    end

    # Índices para Files
    create index(:files, [:ava_id, :created_at], prefix: "ybira", order: [desc: :created_at])
    create index(:files, [:tekoa_id], prefix: "ybira")
    create index(:files, [:folder_id], prefix: "ybira")
    create index(:files, [:file_hash], prefix: "ybira")
    create index(:files, [:deleted_at], prefix: "ybira", where: "deleted_at IS NOT NULL")
    create unique_index(:files, [:public_id], prefix: "ybira")
  end
end
