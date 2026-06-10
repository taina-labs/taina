defmodule Taina.Repo.Migrations.YbiraFase2Indexes do
  @moduledoc """
  Fase 2 do Ybira: soft delete de pastas e índices de paginação por keyset.

  - `ybira.folders.deleted_at` espelha o que `ybira.files` já tem (soft delete).
  - Índices compostos `(escopo, inserted_at DESC, id DESC)` sustentam a
    paginação por cursor sem table scan no portão dos 10k arquivos (RFC 002 §5).
  """

  use Ecto.Migration

  def change do
    alter table(:folders, prefix: "ybira") do
      add :deleted_at, :utc_datetime_usec
    end

    create index(:folders, [:deleted_at],
             prefix: "ybira",
             where: "deleted_at IS NOT NULL",
             name: :ybira_folders_deleted_at_index
           )

    create index(:files, [:folder_id, {:desc, "inserted_at"}, {:desc, "id"}],
             prefix: "ybira",
             name: :ybira_files_folder_id_inserted_at_index
           )

    create index(:files, [:tekoa_id, {:desc, "inserted_at"}, {:desc, "id"}],
             prefix: "ybira",
             name: :ybira_files_tekoa_id_inserted_at_index
           )

    create index(:folders, [:parent_id, {:desc, "inserted_at"}, {:desc, "id"}],
             prefix: "ybira",
             name: :ybira_folders_parent_id_inserted_at_index
           )
  end
end
