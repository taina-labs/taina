defmodule Ypy.Assembleia.Voto do
  @moduledoc """
  O voto de um morador numa proposta: um por pessoa (`(proposta_id,
  ava_id)` e do banco, nao daqui), `:sim` ou `:nao`, enquanto a proposta
  estiver `:aberta`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Assembleia.Proposta
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa

  @type t :: %__MODULE__{
          id: integer() | nil,
          escolha: :sim | :nao,
          tekoa_id: integer() | nil,
          proposta_id: integer() | nil,
          ava_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "assembleia_votos" do
    field(:escolha, Ecto.Enum, values: [:sim, :nao])

    belongs_to(:tekoa, Tekoa)
    belongs_to(:proposta, Proposta)
    belongs_to(:ava, Ava)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(voto, attrs) do
    voto
    |> cast(attrs, [:escolha, :tekoa_id, :proposta_id, :ava_id])
    |> validate_required([:escolha, :tekoa_id, :proposta_id, :ava_id])
    |> unique_constraint(:ava, name: :assembleia_votos_proposta_id_ava_id_index)
  end
end
