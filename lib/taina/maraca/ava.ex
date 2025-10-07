defmodule Taina.Maraca.Ava do
  @moduledoc """
  Representa uma pessoa que usa o Tainá dentro de uma comunidade.

  Cada Ava (pessoa/usuário) pertence a uma Tekoa (comunidade) e pode ter diferentes
  níveis de permissão: admin (administrador) ou member (membro). O nome vem do Tupi-Guarani
  e representa a essência de uma pessoa na comunidade digital.

  ## Campos principais

    * `username` - Nome de usuário único dentro da comunidade
    * `email` - Email para comunicação e login
    * `role` - Função na comunidade (admin ou member)
    * `confirmed_at` - Data/hora em que o email foi confirmado
    * `public_id` - Identificador público seguro (não expõe o ID do banco)
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Guara.Chat
  alias Taina.Guara.Participant
  alias Taina.Maraca.Tekoa

  @schema_prefix "maraca"
  schema "avas" do
    field :username, :string
    field :email, :string
    field :confirmed_at, :utc_datetime_usec
    field :public_id, :string
    field :role, Ecto.Enum, values: ~w(admin member)a, default: :member

    belongs_to :tekoa, Tekoa

    has_many :participants, Participant
    many_to_many :chats, Chat, join_through: Participant

    timestamps()
  end

  @doc """
  Cria ou atualiza um Ava com as informações fornecidas.

  ## Campos obrigatórios

    * `username` - deve ter entre 3 e 50 caracteres
    * `email` - deve ser um email válido e único na comunidade
    * `tekoa_id` - deve referenciar uma Tekoa existente

  ## Exemplos

      iex> changeset(%Ava{}, %{username: "maria", email: "maria@example.com", tekoa_id: 1})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Ava{}, %{username: "ab", email: "invalido"})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(ava, attrs) do
    ava
    |> cast(attrs, [:username, :email, :role, :confirmed_at, :public_id, :tekoa_id])
    |> validate_required([:username, :email, :tekoa_id])
    |> validate_length(:username, min: 3, max: 50)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "deve ser um email válido")
    |> unique_constraint(:email, name: :avas_tekoa_id_email_index)
    |> unique_constraint(:username, name: :avas_tekoa_id_username_index)
    |> validate_inclusion(:role, ~w(admin member)a)
    |> unique_constraint(:public_id)
  end
end
