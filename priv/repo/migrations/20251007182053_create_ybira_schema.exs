defmodule Taina.Repo.Migrations.CreateYbiraSchema do
  use Ecto.Migration

  # Porta para SQLite: tabelas planas (sem schema `ybira`), sem RLS DDL.
  def change do
    create table(:folders) do
      add :ava_id, references(:avas, on_delete: :delete_all), null: false
      add :tekoa_id, references(:tekoas, on_delete: :delete_all), null: false
      add :parent_id, references(:folders, on_delete: :delete_all)
      add :name, :string, null: false
      add :public_id, :string

      timestamps()
    end

    create index(:folders, [:ava_id])
    create index(:folders, [:tekoa_id])
    create index(:folders, [:parent_id], name: :folders_parent_id_index)
    create unique_index(:folders, [:public_id])

    create table(:files) do
      add :ava_id, references(:avas, on_delete: :delete_all), null: false
      add :tekoa_id, references(:tekoas, on_delete: :delete_all), null: false
      add :folder_id, references(:folders, on_delete: :nilify_all)
      add :filename, :string, null: false
      add :original_filename, :string, null: false
      add :filepath, :string, null: false
      add :mime_type, :string, null: false
      add :file_size_bytes, :bigint, null: false
      add :file_hash, :string
      add :metadata, :map, default: %{}
      add :public_id, :string
      add :deleted_at, :utc_datetime_usec

      timestamps()
    end

    # SQLite nao aceita a tupla {:desc, coluna} no helper `create index`;
    # os indices com ordenacao descem como SQL cru.
    execute "CREATE INDEX files_ava_id_inserted_at_index ON files (ava_id, inserted_at DESC, id DESC)"

    create index(:files, [:tekoa_id])
    create index(:files, [:folder_id])
    create index(:files, [:file_hash])
    create index(:files, [:deleted_at], where: "deleted_at IS NOT NULL")
    create unique_index(:files, [:public_id])
  end
end
