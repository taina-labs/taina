defmodule Ypy.Mural.Entry do
  @moduledoc """
  Uma entrada da cadeia unica, tal como o banco a guarda (RFC_006 secao 8).

  O que e assinado e o corpo (`seq`, `prev`, `payload`); `signature` e os 64
  bytes da chave da Tekoa e `cid` e o CID da entrada completa, com assinatura
  incluida, que a entrada seguinte aponta como `prev`. O `tipo` denormalizado
  do payload existe so para o mural legivel filtrar sem operador de JSON.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Tekoa

  @type t :: %__MODULE__{
          id: integer() | nil,
          seq: integer() | nil,
          prev: String.t() | nil,
          tipo: String.t() | nil,
          payload: map() | nil,
          signature: binary() | nil,
          signing_key: binary() | nil,
          cid: String.t() | nil,
          tekoa_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "maraca_mural" do
    field(:cid, :string)
    field(:payload, :map)
    field(:prev, :string)
    field(:seq, :integer)
    field(:signature, :binary)
    field(:signing_key, :binary)

    belongs_to(:tekoa, Tekoa)
    field(:tipo, :string)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "A entrada e append-only: insert ou conflito de sequencia, nada entre."
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:cid, :payload, :prev, :seq, :signature, :signing_key, :tekoa_id, :tipo])
    |> validate_required([:cid, :payload, :seq, :signature, :tekoa_id, :tipo])
    |> validate_number(:seq, greater_than: 0)
    |> unique_constraint(:seq, name: :maraca_mural_tekoa_id_seq_index)
  end
end
