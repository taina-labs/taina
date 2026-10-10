defmodule Taina.Maraca.Event do
  @moduledoc """
  Uma linha do Mural (RFC_003 seção 6, camada 1): o registro append-only de um
  ato da comunidade, "quem fez o quê".

  O evento é consequência de um ato que já aconteceu: nunca é editado nem
  apagado, por isso o schema não tem `updated_at` nem caminho de update. O
  `type` é o vocabulário fixo de atos, todo `type` tem que caber numa frase
  simples na tela; o `payload` guarda o que a frase precisa (nome do arquivo,
  papel do convite, de quanto para quanto a cota mudou).

  `ava_id` é nullable para atos do sistema (sem autor morador), o mural rendera
  "o sistema" nesses casos.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa
  alias Taina.Repo.PublicId

  @type event_type ::
          :invite_created
          | :invite_accepted
          | :member_deactivated
          | :published_to_praca
          | :moved_between_zones
          | :access_requested
          | :access_granted
          | :access_denied
          | :quota_changed

  @type t :: %__MODULE__{
          id: integer() | nil,
          public_id: String.t() | nil,
          type: event_type(),
          payload: map(),
          ava_id: integer() | nil,
          ava: Ava.t() | NotLoaded.t() | nil,
          tekoa_id: integer(),
          tekoa: Tekoa.t() | NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil
        }

  # Vocabulário de atos do mural (RFC_003 seção 6): convite, zonas casa/praca,
  # pedidos de acesso e cota. Mesma palavra no banco, no contexto e na tela.
  @event_types ~w(invite_created invite_accepted member_deactivated published_to_praca
    moved_between_zones access_requested access_granted access_denied quota_changed)a

  @schema_prefix "maraca"
  schema "events" do
    field :public_id, PublicId, autogenerate: true
    field :type, Ecto.Enum, values: @event_types
    field :payload, :map, default: %{}

    belongs_to :ava, Ava
    belongs_to :tekoa, Tekoa

    # Ledger append-only: sem `updated_at`, sem caminho de update.
    timestamps(updated_at: false)
  end

  @doc """
  Grava uma linha do mural.

  `type`, `ava_id` e `tekoa_id` são programáticos, definidos pelo contexto que
  registrou o ato (nunca vindos de input), só o `payload` entra por cast.

  ## Campos obrigatórios

    * `type` - o ato, do vocabulário fixo do mural
    * `tekoa_id` - a comunidade onde o ato aconteceu
    * `payload` - detalhes da frase (nome, papel, valores)

  ## Exemplos

      iex> changeset(%Event{}, %{type: :invite_created, tekoa_id: 1, payload: %{}})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Event{}, %{type: :coisa_esquisita, tekoa_id: 1, payload: %{}})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:type, :ava_id, :tekoa_id, :payload])
    |> validate_required([:type, :tekoa_id, :payload])
    |> unique_constraint(:public_id)
  end
end
