defmodule Taina.Guara.Message do
  @moduledoc """
  Representa uma mensagem enviada em um chat do Guará.

  Cada mensagem pertence a um chat e foi enviada por uma pessoa (Ava). Mensagens
  podem ter texto, arquivos anexados (fotos, vídeos, documentos), ou ambos. Também
  é possível responder a outras mensagens, criando threads de conversa.

  ## Campos principais

    * `content` - Texto da mensagem
    * `message_type` - Tipo: :text, :image, :video, :audio, :file
    * `public_id` - Identificador público seguro
    * `parent_id` - Mensagem sendo respondida (opcional)

  ## Anexos

  Quando a mensagem tem um arquivo anexado (foto, vídeo, etc), ele é armazenado
  no Ybira e referenciado através de `file_id`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Taina.Guara.Chat
  alias Taina.Maraca.Ava
  alias Taina.Ybira.File

  @schema_prefix "guara"
  schema "messages" do
    field :content, :string
    field :public_id, :string

    field :message_type, Ecto.Enum,
      values: ~w(text image video audio file)a,
      default: :text

    field :metadata, :map, default: %{}

    belongs_to :chat, Chat
    belongs_to :sender, Ava
    belongs_to :parent, __MODULE__
    belongs_to :file, File

    timestamps()
  end

  @doc """
  Cria ou atualiza uma mensagem com as informações fornecidas.

  ## Campos obrigatórios

    * `chat_id` - chat onde a mensagem foi enviada
    * `sender_id` - pessoa que enviou a mensagem
    * `content` OU `file_id` - mensagem deve ter texto ou arquivo (ou ambos)

  ## Campos opcionais

    * `parent_id` - para responder outra mensagem
    * `message_type` - tipo da mensagem (padrão: :text)
    * `file_id` - arquivo anexado (foto, vídeo, etc)
    * `metadata` - informações extras (JSON)

  ## Exemplos

      iex> changeset(%Message{}, %{content: "Olá!", chat_id: 1, sender_id: 1})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Message{}, %{file_id: 123, message_type: :image, chat_id: 1, sender_id: 1})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Message{}, %{chat_id: 1, sender_id: 1})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [
      :content,
      :public_id,
      :message_type,
      :metadata,
      :chat_id,
      :sender_id,
      :parent_id,
      :file_id
    ])
    |> validate_required([:chat_id, :sender_id])
    |> validate_inclusion(:message_type, ~w(text image video audio file)a)
    |> validate_content_or_file()
    |> foreign_key_constraint(:chat_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:parent_id)
    |> foreign_key_constraint(:file_id)
  end

  defp validate_content_or_file(changeset) do
    content = get_field(changeset, :content)
    file_id = get_field(changeset, :file_id)

    if is_nil(content) and is_nil(file_id) do
      add_error(changeset, :content, "mensagem deve ter texto ou arquivo anexado")
    else
      changeset
    end
  end
end
