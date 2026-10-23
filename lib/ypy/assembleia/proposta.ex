defmodule Ypy.Assembleia.Proposta do
  @moduledoc """
  A proposta da assembleia (RFC_003 secao 8): o ato sensivel que a comunidade
  ve e vota. O `payload` carrega o alvo do ato em identificadores publicos; a
  execucao do ato aprovado e do produto, que reclama aqui a executacao uma
  vez (`executado_em`), para que nenhuma proposta vire dois atos.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.PublicId

  @tipos [:remover_morador, :nomear_zelador, :destituir_zelador, :mudar_cota]
  @status [:aberta, :aprovada, :rejeitada, :expirada]

  @type t :: %__MODULE__{
          id: integer() | nil,
          tipo: :remover_morador | :nomear_zelador | :destituir_zelador | :mudar_cota,
          payload: map(),
          status: :aberta | :aprovada | :rejeitada | :expirada,
          fecha_em: DateTime.t() | nil,
          executado_em: DateTime.t() | nil,
          public_id: String.t() | nil,
          tekoa_id: integer() | nil,
          autor_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "assembleia_propostas" do
    field(:tipo, Ecto.Enum, values: @tipos)
    field(:payload, :map, default: %{})
    field(:status, Ecto.Enum, values: @status, default: :aberta)
    field(:fecha_em, :utc_datetime)
    field(:executado_em, :utc_datetime)
    field(:public_id, PublicId, autogenerate: true)

    belongs_to(:tekoa, Tekoa)
    belongs_to(:autor, Ava)

    timestamps(type: :utc_datetime)
  end

  @doc "Abre a proposta. O prazo (`fecha_em`) e decisao de quem abre."
  def changeset(proposta, attrs) do
    proposta
    |> cast(attrs, [:tipo, :payload, :fecha_em, :tekoa_id, :autor_id])
    |> validate_required([:tipo, :fecha_em, :tekoa_id, :autor_id])
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:autor_id)
    |> unique_constraint(:public_id)
  end

  @doc "Registra o resultado do escrutinio."
  def fechar_changeset(proposta, resultado) when resultado in [:aprovada, :rejeitada, :expirada] do
    change(proposta, status: resultado)
  end
end
