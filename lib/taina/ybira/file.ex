defmodule Taina.Ybira.File do
  @moduledoc """
  Representa um arquivo armazenado no Ybira.

  Ybira é seu espaço de armazenamento pessoal na comunidade. Cada arquivo pode ser
  uma foto, documento, vídeo ou qualquer tipo de arquivo que você queira guardar de
  forma segura. Os arquivos podem ficar soltos ou organizados dentro de pastas.

  ## Campos principais

    * `filename` - Nome do arquivo como está salvo no disco (ex: "abc123.jpg")
    * `original_filename` - Nome original que você deu (ex: "minhas_ferias.jpg")
    * `filepath` - Caminho completo onde o arquivo está guardado
    * `mime_type` - Tipo do arquivo (ex: "image/jpeg", "application/pdf")
    * `file_size_bytes` - Tamanho do arquivo em bytes
    * `file_hash` - Hash SHA-256 para evitar duplicação de arquivos
    * `metadata` - Informações extras sobre o arquivo (JSON)
    * `public_id` - Identificador público seguro
    * `deleted_at` - Quando foi deletado (soft delete - fica 30 dias antes de apagar)
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa
  alias Taina.Ybira.Folder

  @schema_prefix "ybira"
  schema "files" do
    field :filename, :string
    field :original_filename, :string
    field :filepath, :string
    field :mime_type, :string
    field :file_size_bytes, :integer
    field :file_hash, :string
    field :metadata, :map, default: %{}
    field :public_id, :string
    field :deleted_at, :naive_datetime

    belongs_to :ava, Ava
    belongs_to :tekoa, Tekoa
    belongs_to :folder, Folder

    timestamps()
  end

  @doc """
  Cria ou atualiza um arquivo com as informações fornecidas.

  ## Campos obrigatórios

    * `filename` - nome do arquivo no disco (gerado automaticamente)
    * `original_filename` - nome original que o usuário deu ao arquivo
    * `filepath` - caminho onde o arquivo está salvo
    * `mime_type` - tipo MIME do arquivo
    * `file_size_bytes` - tamanho do arquivo em bytes
    * `ava_id` - pessoa dona do arquivo
    * `tekoa_id` - comunidade onde o arquivo existe

  ## Exemplos

      iex> changeset(%File{}, %{
      ...>   filename: "abc123.jpg",
      ...>   original_filename: "minhas_ferias.jpg",
      ...>   filepath: "/storage/abc123.jpg",
      ...>   mime_type: "image/jpeg",
      ...>   file_size_bytes: 1024,
      ...>   file_hash: "sha256...",
      ...>   ava_id: 1,
      ...>   tekoa_id: 1
      ...> })
      %Ecto.Changeset{valid?: true}

      iex> changeset(%File{}, %{filename: "teste.pdf"})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :filename,
      :original_filename,
      :filepath,
      :mime_type,
      :file_size_bytes,
      :file_hash,
      :metadata,
      :public_id,
      :deleted_at,
      :ava_id,
      :tekoa_id,
      :folder_id
    ])
    |> validate_required([
      :filename,
      :original_filename,
      :filepath,
      :mime_type,
      :file_size_bytes,
      :ava_id,
      :tekoa_id
    ])
    |> validate_length(:filename, min: 1, max: 255)
    |> validate_length(:original_filename, min: 1, max: 255)
    |> validate_number(:file_size_bytes, greater_than: 0)
    |> foreign_key_constraint(:ava_id)
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:folder_id)
  end
end
