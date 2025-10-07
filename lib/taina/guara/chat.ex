defmodule Taina.Guara.Chat do
  @moduledoc """
  Representa uma conversa no Guará (mensageiro).

  No Tainá, não distinguimos entre "conversa direta" e "grupo" - todo chat é
  tratado igualmente! Isso dá muita flexibilidade: você pode conversar consigo
  mesmo (como notas pessoais), com outra pessoa, ou com várias pessoas.

  ## Filosofia: Sem distinção entre DM e Grupo

  Um chat pode ter:
  - **1 participante**: Você conversando consigo mesmo (notas, lembretes)
  - **2 participantes**: Conversa tradicional entre duas pessoas
  - **3+ participantes**: Grupo com várias pessoas

  Não há limite técnico nem distinção - todos são "chats"! Quem cria o chat
  é automaticamente admin e pode adicionar mais pessoas quando quiser.

  ## Campos principais

    * `name` - Nome do chat (opcional - útil para grupos)
    * `icon` - Ícone ou imagem do chat (opcional)
    * `public_id` - Identificador público seguro

  ## Participantes

  Os participantes são gerenciados através da tabela `Participant`, que
  também rastreia quem é admin, quando entrou, e mensagens entregues (✓✓).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Guara.Message
  alias Taina.Guara.Participant
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa

  @schema_prefix "guara"
  schema "chats" do
    field :public_id, :string
    field :name, :string
    field :icon, :string

    belongs_to :tekoa, Tekoa
    belongs_to :created_by, Ava

    has_many :messages, Message
    has_many :participants, Participant
    many_to_many :avas, Ava, join_through: Participant

    timestamps()
  end

  @doc """
  Cria ou atualiza um chat com as informações fornecidas.

  ## Campos obrigatórios

    * `tekoa_id` - comunidade onde o chat existe
    * `created_by_id` - pessoa que criou o chat (será admin automaticamente)

  ## Campos opcionais

    * `name` - nome do chat (útil para grupos, opcional)
    * `icon` - ícone do chat

  ## Exemplos

      iex> changeset(%Chat{}, %{name: "Família", tekoa_id: 1, created_by_id: 1})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Chat{}, %{tekoa_id: 1, created_by_id: 1})
      %Ecto.Changeset{valid?: true}

  ## Nota sobre participantes

  Os participantes devem ser adicionados via `Taina.Guara.Participant` após
  criar o chat. O criador é automaticamente o primeiro participante (admin).
  """
  def changeset(chat, attrs) do
    chat
    |> cast(attrs, [:name, :icon, :public_id, :tekoa_id, :created_by_id])
    |> validate_required([:tekoa_id, :created_by_id])
    |> validate_length(:name, max: 255)
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:created_by_id)
    |> unique_constraint(:public_id)
  end
end
