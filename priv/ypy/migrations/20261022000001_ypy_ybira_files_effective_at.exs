defmodule YpyYbiraFilesEffectiveAt do
  @moduledoc """
  A dica local de ordem da linha do tempo: o produto preenche `effective_at`
  (a data de captura, por exemplo) e ordena por `COALESCE(effective_at,
  inserted_at)`, ordem que o indice de expressao cobre em vez de varrer a
  tabela.
  """

  use Ecto.Migration

  def up do
    alter table(:ybira_files) do
      add :effective_at, :utc_datetime
    end

    execute("""
    CREATE INDEX ybira_files_effective_at_index
      ON ybira_files (COALESCE(effective_at, inserted_at) DESC, id DESC)
    """)
  end

  def down do
    execute("DROP INDEX ybira_files_effective_at_index")

    alter table(:ybira_files) do
      remove :effective_at
    end
  end
end
