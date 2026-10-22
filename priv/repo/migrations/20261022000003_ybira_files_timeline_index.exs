defmodule Taina.Repo.Migrations.YbiraFilesTimelineIndex do
  @moduledoc """
  O indice da linha do tempo do Jaci, na expressao que a consulta usa.

  A linha do tempo (`Taina.Jaci.timeline/2`) ordena por `COALESCE(CAST(
  strftime('%s', effective_at) AS INTEGER), CAST(strftime('%s', inserted_at)
  AS INTEGER)) DESC, id DESC`: as duas fontes de data efetiva (EXIF e
  fallback do upload) normalizadas para epoch de segundos. O indice anterior
  (`ybira_files_effective_at_index`, sobre `COALESCE(effective_at,
  inserted_at) DESC, id DESC`) nao casa com essa expressao, e o SQLite
  terminava a consulta em `USE TEMP B-TREE FOR ORDER BY`.

  Este indice reproduz a expressao EXATA da consulta e lidera com
  `tekoa_id`: o planner usa o mesmo indice na igualdade do `WHERE tekoa_id
  = ?` (o guard do contexto de Tekoa) e na ordem, sem sort temporario.
  """

  use Ecto.Migration

  def up do
    execute("DROP INDEX IF EXISTS ybira_files_effective_at_index")

    execute("""
    CREATE INDEX ybira_files_timeline_index
      ON ybira_files (
        tekoa_id,
        COALESCE(CAST(strftime('%s', effective_at) AS INTEGER), CAST(strftime('%s', inserted_at) AS INTEGER)) DESC,
        id DESC
      )
    """)
  end

  def down do
    execute("DROP INDEX IF EXISTS ybira_files_timeline_index")

    execute("""
    CREATE INDEX ybira_files_effective_at_index
      ON ybira_files (COALESCE(effective_at, inserted_at) DESC, id DESC)
    """)
  end
end
