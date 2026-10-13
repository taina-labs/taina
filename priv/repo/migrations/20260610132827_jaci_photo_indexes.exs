defmodule Taina.Repo.Migrations.JaciPhotoIndexes do
  @moduledoc """
  Fase 3 (Jaci-lite): índice parcial que sustenta a galeria sobre as imagens do
  Ybira, no portão dos 5k fotos fluindo num Pi 5 (RFC 002, §5).

  Filtra para imagens não-deletadas (`mime_type LIKE 'image/%'`), então fica
  pequeno e seletivo mesmo num acervo majoritariamente de documentos, e serve
  tanto a grade (keyset por upload `inserted_at DESC, id DESC`) quanto o filtro
  inicial da linha do tempo.

  ## Por que não há índice para a ordenação da linha do tempo

  A linha do tempo ordena pela data efetiva: `taken_at` do EXIF quando existe,
  senao `inserted_at`. No Postgres o `::timestamp` dependia de `DateStyle`, e
  no SQLite o valor vem de `json_extract` (nao indexavel como ordenacao
  estavel de keyset). Em ambos, a ordenacao fica como sort em memoria: com o
  teto de 5k imagens por Tekoa do MVP, e sub-milissegundo sobre o conjunto ja
  filtrado por este indice. Se o benchmark do Pi (gate da Fase 3) mostrar que
  importa, a saida e uma coluna `photo_taken_at` populada pelo worker de
  rendition, indexavel e keyset-perfeita.
  """

  use Ecto.Migration

  def up do
    execute """
    CREATE INDEX ybira_files_images_index
    ON files (inserted_at DESC, id DESC)
    WHERE deleted_at IS NULL AND substr(mime_type, 1, 6) = 'image/'
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS ybira_files_images_index"
  end
end
