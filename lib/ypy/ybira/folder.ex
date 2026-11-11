defmodule Ypy.Ybira.Folder do
  @moduledoc """
  A pasta que organiza arquivos, tambem ela um record enderecado por `rkey`.

  A zona e propria e nao cascateia para os arquivos (RFC_003 D1); o aninho
  dentro de outra pasta vem de `parent_id`, e o produto resolve ciclos na
  borda (o kernel nao move pasta, so arquivo).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa

  @type t :: %__MODULE__{
          id: integer() | nil,
          rkey: String.t() | nil,
          cid: String.t() | nil,
          nome: String.t() | nil,
          zona: :casa | :praca,
          apagado_em: DateTime.t() | nil,
          tekoa_id: integer() | nil,
          dono_id: integer() | nil,
          parent_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "ybira_folders" do
    field(:apagado_em, :utc_datetime)
    field(:cid, :string)
    belongs_to(:dono, Ava)
    field(:nome, :string)
    belongs_to(:parent, __MODULE__)
    field(:rkey, :string)

    belongs_to(:tekoa, Tekoa)
    field(:zona, Ecto.Enum, values: [:casa, :praca], default: :casa)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria a pasta. `rkey` e `cid` (do envelope) sao programaticos."
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:cid, :dono_id, :nome, :parent_id, :rkey, :tekoa_id, :zona])
    |> validate_required([:cid, :dono_id, :nome, :rkey, :tekoa_id])
    |> validate_inclusion(:zona, [:casa, :praca])
    |> validate_length(:nome, min: 1, max: 255)
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:dono_id)
    |> foreign_key_constraint(:parent_id)
    |> unique_constraint(:rkey, name: :ybira_folders_tekoa_id_rkey_index)
  end

  @doc "Troca o envelope (renomear) e o nome."
  def record_changeset(folder, attrs) do
    folder
    |> cast(attrs, [:cid, :nome])
    |> validate_required([:cid, :nome])
    |> validate_length(:nome, min: 1, max: 255)
  end
end
