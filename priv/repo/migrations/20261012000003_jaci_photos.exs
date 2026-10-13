defmodule Taina.Repo.Migrations.JaciPhotos do
  @moduledoc """
  A casa dos metadados de foto do Jaci (produto): o `ybira_files` do kernel
  nao tem coluna de metadata (RFC_006 secao 7: o produto acrescenta as
  proprias tabelas, sem tocar a forma das tabelas do kernel). O worker de
  renditions grava aqui dimensoes, `taken_at` do EXIF e os caminhos de
  thumbnail; a galeria le deste join.
  """

  use Ecto.Migration

  def change do
    create table(:jaci_photos) do
      add :file_id, references(:ybira_files, on_delete: :delete_all), null: false
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:jaci_photos, [:file_id])

    # Grade do Jaci: imagens nao apagadas, da mais recente para a mais antiga.
    execute """
    CREATE INDEX ybira_files_images_index
    ON ybira_files (inserted_at DESC, id DESC)
    WHERE apagado_em IS NULL AND substr(mime, 1, 6) = 'image/'
    """
  end
end
