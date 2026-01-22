defmodule Taina.Maraca.Tekoa do
  @moduledoc """
  Representa uma comunidade no Tainá.

  Tekoa vem do Tupi-Guarani e significa "lugar onde se vive" ou "aldeia". É a base
  para organização das pessoas (Avas), arquivos, conversas e tudo que a comunidade
  compartilha. Cada Tekoa é independente e tem controle total sobre seus dados.

  ## Campos principais

    * `name` - Nome da comunidade (deve ser único)
    * `public_id` - Identificador público seguro
    * `settings` - Configurações personalizadas da comunidade (JSON)
    * `storage_quota_gb` - Limite de armazenamento em gigabytes
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Repo.PublicId

  @schema_prefix "maraca"
  schema "tekoas" do
    field :name, :string
    field :public_id, PublicId, autogenerate: true
    field :settings, :map, default: %{}
    field :storage_quota_bytes, :integer
    field :storage_used_bytes, :integer, default: 0

    has_many :avas, Taina.Maraca.Ava

    timestamps()
  end

  @doc """
  Cria ou atualiza uma Tekoa com as informações fornecidas.

  ## Campos obrigatórios

    * `name` - deve ter entre 3 e 100 caracteres e ser único

  ## Exemplos

      iex> changeset(%Tekoa{}, %{name: "Minha Comunidade", storage_quota: 500})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Tekoa{}, %{name: "ab"})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(tekoa, attrs) do
    tekoa
    |> cast(attrs, [:name, :settings, :storage_quota_bytes])
    |> validate_required([:name, :storage_quota_bytes])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_number(:storage_quota_bytes, greater_than: 0)
    |> unique_constraint(:name)
    |> unique_constraint(:public_id)
  end
end
