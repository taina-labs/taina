defmodule Taina.Repo.Migrations.JaciPhotoIndexes do
  @moduledoc """
  Fase 3 (Jaci-lite): índice parcial que sustenta a galeria sobre as imagens do
  Ybira, no portão dos 5k fotos fluindo num Pi 5 (RFC 002, §5).

  Filtra para imagens não-deletadas (`mime_type LIKE 'image/%'`), então fica
  pequeno e seletivo mesmo num acervo majoritariamente de documentos, e serve
  tanto a grade (keyset por upload `inserted_at DESC, id DESC`) quanto o filtro
  inicial da linha do tempo.

  ## Por que não há índice para a ordenação da linha do tempo

  A linha do tempo ordena pela data efetiva — `COALESCE((metadata->>'taken_at')
  ::timestamp, inserted_at)`. Esse `::timestamp` depende de `DateStyle`, então é
  *stable*, não *immutable*, e o Postgres recusa indexá-lo. Em vez de mentir
  para o planner (função `IMMUTABLE` falsa) ou trocar o formato do EXIF por
  epoch, deixamos a ordenação como um sort em memória: com o teto de 5k imagens
  por Tekoa do MVP, é sub-milissegundo sobre o conjunto já filtrado por este
  índice. Se o benchmark do Pi (gate da Fase 3) mostrar que importa, a saída é
  uma coluna `photo_taken_at` populada pelo worker de rendition — indexável e
  keyset-perfeita — sem mexer no formato do `metadata`.
  """

  use Ecto.Migration

  def up do
    execute """
    CREATE INDEX ybira_files_images_index
    ON ybira.files (inserted_at DESC, id DESC)
    WHERE deleted_at IS NULL AND mime_type LIKE 'image/%'
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS ybira.ybira_files_images_index"
  end
end
