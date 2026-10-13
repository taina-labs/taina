defmodule Taina.Repo.Migrations.YbiraFase2Indexes do
  @moduledoc """
  Fase 2 do Ybira: soft delete de pastas e índices de paginação por keyset.

  - `folders.deleted_at` espelha o que `files` já tem (soft delete).
  - Índices compostos `(escopo, inserted_at DESC, id DESC)` sustentam a
    paginação por cursor sem table scan no portão dos 10k arquivos (RFC 002 §5).
  """

  use Ecto.Migration

  def change do
    alter table(:folders) do
      add :deleted_at, :utc_datetime_usec
    end

    create index(:folders, [:deleted_at],
             where: "deleted_at IS NOT NULL",
             name: :ybira_folders_deleted_at_index
           )

    execute "CREATE INDEX ybira_files_folder_id_inserted_at_index ON files (folder_id, inserted_at DESC, id DESC)"

    execute "CREATE INDEX ybira_files_tekoa_id_inserted_at_index ON files (tekoa_id, inserted_at DESC, id DESC)"

    execute "CREATE INDEX ybira_folders_parent_id_inserted_at_index ON folders (parent_id, inserted_at DESC, id DESC)"
  end
end
