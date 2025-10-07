defmodule Taina.Ybira.Folder do
  @moduledoc """
  Representa uma pasta para organizar arquivos no Ybira.

  As pastas funcionam como no seu computador: você pode criar pastas dentro de outras
  pastas (subpastas) para organizar melhor seus arquivos. Cada pasta pertence a uma
  pessoa (Ava) e a uma comunidade (Tekoa).

  ## Campos principais

    * `name` - Nome da pasta (ex: "Documentos", "Fotos de Família")
    * `public_id` - Identificador público seguro
    * `folder_id` - Pasta pai (quando esta pasta está dentro de outra)
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa

  @schema_prefix "ybira"
  schema "folders" do
    field :name, :string
    field :public_id, :string

    belongs_to :ava, Ava
    belongs_to :tekoa, Tekoa
    belongs_to :folder, __MODULE__

    timestamps()
  end

  @doc """
  Cria ou atualiza uma pasta com as informações fornecidas.

  ## Campos obrigatórios

    * `name` - deve ter entre 1 e 255 caracteres
    * `ava_id` - pessoa dona da pasta
    * `tekoa_id` - comunidade onde a pasta existe

  ## Exemplos

      iex> changeset(%Folder{}, %{name: "Meus Documentos", ava_id: 1, tekoa_id: 1})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Folder{}, %{name: ""})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:name, :public_id, :ava_id, :tekoa_id, :folder_id])
    |> validate_required([:name, :ava_id, :tekoa_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:ava_id)
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:folder_id)
    |> unique_constraint(:public_id)
  end
end
