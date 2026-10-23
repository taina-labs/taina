defmodule Ypy.Ybira.Record do
  @moduledoc """
  O arquivo do envelope de record (o do nucleo e `Ypy.Record`, o fio): cada
  versao do envelope de um arquivo ou pasta, com o CID dela.

  Append-only: renomear e mover nao sobrescrevem, adicionam um envelope novo
  e o recurso passa a apontar para ele. O dado do record e o fio DAG-CBOR
  montado (`$type`, `rkey`, `actor`, `created_at`, `payload`), em `:map` para
  a exportacao reencodar byte a byte.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Tekoa

  @type t :: %__MODULE__{
          id: integer() | nil,
          rkey: String.t() | nil,
          collection: String.t() | nil,
          cid: String.t() | nil,
          record: map() | nil,
          tekoa_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "ybira_records" do
    field(:rkey, :string)
    field(:collection, :string)
    field(:cid, :string)
    field(:record, :map)

    belongs_to(:tekoa, Tekoa)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:rkey, :collection, :cid, :record, :tekoa_id])
    |> validate_required([:rkey, :collection, :cid, :record, :tekoa_id])
    |> unique_constraint(:cid, name: :ybira_records_tekoa_id_cid_index)
  end
end
