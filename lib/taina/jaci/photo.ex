defmodule Taina.Jaci.Photo do
  @moduledoc """
  Os metadados de foto do Jaci (produto): dimensoes, data de captura do EXIF
  e caminhos de thumbnail, gravados pelo worker de renditions. O `ybira_files`
  do kernel nao tem coluna de metadata (RFC_006 secao 7: o produto acrescenta
  as proprias tabelas, sem tocar a forma das do kernel); o que aqui existe e
  rendicao, nada de conteudo.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Ybira.File

  @type t :: %__MODULE__{
          id: integer() | nil,
          file_id: integer() | nil,
          metadata: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "jaci_photos" do
    field :metadata, :map, default: %{}

    belongs_to :file, File

    timestamps(type: :utc_datetime)
  end

  @doc "Cria ou atualiza a rendicao de um arquivo. O file_id e programatico."
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:metadata])
    |> validate_required([:file_id])
    |> unique_constraint(:file_id)
    |> foreign_key_constraint(:file_id)
  end
end
