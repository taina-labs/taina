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
  alias Ypy.Tid

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
    field(:rkey, :string)
    field(:cid, :string)
    field(:nome, :string)
    field(:zona, Ecto.Enum, values: [:casa, :praca], default: :casa)
    field(:apagado_em, :utc_datetime)

    belongs_to(:tekoa, Tekoa)
    belongs_to(:dono, Ava)
    belongs_to(:parent, __MODULE__)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria a pasta. `rkey` e `cid` (do envelope) sao programaticos."
  def changeset(folder, attrs) do
    folder
    |> cast(attrs, [:rkey, :cid, :nome, :zona, :tekoa_id, :dono_id, :parent_id])
    |> validate_required([:rkey, :cid, :nome, :tekoa_id, :dono_id])
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

  @doc "Muda a zona. Idempotente: a mesma zona e no-op valido."
  def zona_changeset(folder, zona) when zona in [:casa, :praca] do
    change(folder, zona: zona)
  end

  @doc "Lixeira."
  def trash_changeset(folder, agora) do
    change(folder, apagado_em: agora)
  end

  @doc "Ressuscita da lixeira."
  def restore_changeset(folder) do
    change(folder, apagado_em: nil)
  end

  @doc "O proximo rkey (TID) de pasta, a partir de agora."
  def next_rkey do
    micros = System.os_time(:microsecond)
    clock = rem(:erlang.unique_integer([:positive]), 1024)
    {rkey, _int} = Tid.next(0, micros, clock)
    rkey
  end
end
