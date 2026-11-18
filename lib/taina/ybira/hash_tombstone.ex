defmodule Taina.Ybira.HashTombstone do
  @moduledoc """
  A permanent record that an owner purged a file with this hash.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa

  @type t :: %__MODULE__{
          id: integer() | nil,
          tekoa_id: integer() | nil,
          dono_id: integer() | nil,
          hash: String.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "ybira_hash_tombstones" do
    belongs_to(:dono, Ava)
    field(:hash, :string)
    belongs_to(:tekoa, Tekoa)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Validates a permanent owner/hash tombstone."
  def changeset(tombstone, attrs) do
    tombstone
    |> cast(attrs, [:hash])
    |> validate_required([:dono_id, :hash, :tekoa_id])
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:dono_id)
    |> unique_constraint([:tekoa_id, :dono_id, :hash],
      name: :ybira_hash_tombstones_tekoa_id_dono_id_hash_index
    )
  end
end
