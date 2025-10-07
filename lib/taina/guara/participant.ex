defmodule Taina.Guara.Participant do
  @moduledoc """
  Representa a participação de uma pessoa (Ava) em um chat do Guará.

  Cada participante tem informações sobre quando entrou no chat, quando viu
  mensagens pela última vez, e se é administrador. Isso permite rastrear quem
  faz parte de cada conversa e implementar funcionalidades como:

  - Marcar mensagens como entregues (✓✓)
  - Saber quem pode adicionar/remover pessoas
  - Histórico de quando cada pessoa entrou

  ## Campos principais

    * `joined_at` - Quando a pessoa entrou no chat
    * `last_read_at` - Última vez que viu mensagens (para marcar como entregue)
    * `role` - Função: :admin (pode gerenciar) ou :member (participante normal)

  ## Sobre administradores

  Quem cria o chat é automaticamente admin. Admins podem:
  - Adicionar novas pessoas ao chat
  - Promover outros participantes a admin
  - Mudar nome/ícone do chat (se for grupo)

  ## Nota importante

  Um chat pode ter:
  - 1 pessoa: você conversando consigo mesmo (notas pessoais)
  - 2 pessoas: conversa entre duas pessoas (tradicional "DM")
  - 3+ pessoas: grupo

  Não há distinção técnica entre esses tipos - todos são tratados igualmente!
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Guara.Chat
  alias Taina.Maraca.Ava

  @schema_prefix "guara"
  @primary_key false
  schema "participants" do
    belongs_to :chat, Chat, primary_key: true
    belongs_to :ava, Ava, primary_key: true

    field :joined_at, :naive_datetime
    field :last_read_at, :naive_datetime
    field :role, Ecto.Enum, values: ~w(admin member)a, default: :member

    timestamps()
  end

  @doc """
  Cria ou atualiza um participante com as informações fornecidas.

  ## Campos obrigatórios

    * `chat_id` - chat do qual a pessoa faz parte
    * `ava_id` - pessoa que participa do chat
    * `joined_at` - quando entrou (geralmente DateTime.utc_now())

  ## Campos opcionais

    * `role` - :admin ou :member (padrão: :member)
    * `last_read_at` - última mensagem vista

  ## Exemplos

      iex> changeset(%Participant{}, %{chat_id: 1, ava_id: 1, joined_at: ~N[2025-01-01 10:00:00]})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Participant{}, %{chat_id: 1, ava_id: 1, joined_at: ~N[2025-01-01 10:00:00], role: :admin})
      %Ecto.Changeset{valid?: true}
  """
  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:chat_id, :ava_id, :joined_at, :last_read_at, :role])
    |> validate_required([:chat_id, :ava_id, :joined_at])
    |> validate_inclusion(:role, ~w(admin member)a)
    |> foreign_key_constraint(:chat_id)
    |> foreign_key_constraint(:ava_id)
    |> unique_constraint([:chat_id, :ava_id], name: :participants_chat_id_ava_id_index)
  end
end
