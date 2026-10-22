defmodule Taina.Repo.Migrations.JaciTimelineTakenAtIndex do
  @moduledoc """
  Índice de expressão para a linha do tempo do Jaci (revisão 0.1.0, seção 4).

  A linha do tempo ordena e pagina por `(data efetiva, id)`, em que a data
  efetiva vem de `COALESCE(json_extract(metadata, '$.taken_at'),
  inserted_at)` normalizada para epoch de segundos (`Taina.Jaci`). Este
  índice guarda a parcela do `taken_at` já normalizada, na mesma expressão
  da consulta, para que planos guiados por `jaci_photos` (e consultas
  futuras por faixa de data de captura) não virem scan.

  O SQLite não cria índice de expressão atravessando duas tabelas, então a
  parcela do fallback (`inserted_at`, coluna do kernel) não entra aqui: a
  consulta completa ainda ordena o conjunto legível. Eliminar essa
  ordenação de vez exigiria uma coluna de epoch efetivo na tabela do kernel
  (ypy), fora do escopo desta rodada.
  """

  use Ecto.Migration

  def change do
    execute(
      """
      CREATE INDEX jaci_photos_taken_at_index
      ON jaci_photos (
        CAST(strftime('%s', json_extract(metadata, '$.taken_at')) AS INTEGER),
        file_id
      )
      """,
      "DROP INDEX IF EXISTS jaci_photos_taken_at_index"
    )
  end
end
