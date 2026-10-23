defmodule Ypy.Ybira.File do
  @moduledoc """
  O arquivo da comunidade, enderecado pelo `rkey` (TID, id publico, RFC_006
  secao 12). Os bytes moram no `Ypy.BlobStore` pelo `blob_cid`; o envelope
  assinado (`cid`) e alcancavel pela cadeia e arquivado em `Ypy.Ybira.Record`.

  A zona nasce `:casa` (RFC_003 D1) e so o dono muda; `apagado_em` e a
  lixeira, que os bytes ficam no blob ate o produto expurgar.

  O `effective_at` e uma dica local de ordem que o produto preenche com a
  data de captura (como a `zona`, nao faz parte do record assinado): a linha
  do tempo ordena por `COALESCE(effective_at, inserted_at)`, coberta pelo
  indice de expressao `ybira_files_effective_at_index`.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.Tid
  alias Ypy.Ybira.Folder

  @type t :: %__MODULE__{
          id: integer() | nil,
          rkey: String.t() | nil,
          cid: String.t() | nil,
          blob_cid: String.t() | nil,
          nome: String.t() | nil,
          mime: String.t() | nil,
          tamanho: integer() | nil,
          hash: String.t() | nil,
          zona: :casa | :praca,
          apagado_em: DateTime.t() | nil,
          effective_at: DateTime.t() | nil,
          tekoa_id: integer() | nil,
          dono_id: integer() | nil,
          folder_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "ybira_files" do
    field(:rkey, :string)
    field(:cid, :string)
    field(:blob_cid, :string)
    field(:nome, :string)
    field(:mime, :string)
    field(:tamanho, :integer)
    field(:hash, :string)
    field(:zona, Ecto.Enum, values: [:casa, :praca], default: :casa)
    field(:apagado_em, :utc_datetime)
    field(:effective_at, :utc_datetime)

    belongs_to(:tekoa, Tekoa)
    belongs_to(:dono, Ava)
    belongs_to(:folder, Folder)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria o arquivo. `rkey` e `cid` (do envelope) sao programaticos."
  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :rkey,
      :cid,
      :blob_cid,
      :nome,
      :mime,
      :tamanho,
      :hash,
      :zona,
      :tekoa_id,
      :dono_id,
      :folder_id,
      :effective_at
    ])
    |> validate_required([
      :rkey,
      :cid,
      :blob_cid,
      :nome,
      :mime,
      :tamanho,
      :hash,
      :tekoa_id,
      :dono_id
    ])
    |> validate_number(:tamanho, greater_than: 0)
    |> validate_inclusion(:zona, [:casa, :praca])
    |> validate_length(:nome, min: 1, max: 255)
    |> foreign_key_constraint(:tekoa_id)
    |> foreign_key_constraint(:dono_id)
    |> foreign_key_constraint(:folder_id)
    |> unique_constraint(:rkey, name: :ybira_files_tekoa_id_rkey_index)
  end

  @doc "Troca o envelope (versao nova do record) e o dado que ele descreve."
  def record_changeset(file, attrs) do
    file
    |> cast(attrs, [:cid, :nome, :folder_id])
    |> validate_required([:cid, :nome])
    |> validate_length(:nome, min: 1, max: 255)
  end

  @doc "Muda a zona. Idempotente: a mesma zona e no-op valido."
  def zona_changeset(file, zona) when zona in [:casa, :praca] do
    change(file, zona: zona)
  end

  @doc "Lixeira: apaga suave, os bytes ficam ate o produto expurgar."
  def trash_changeset(file, agora) do
    change(file, apagado_em: agora)
  end

  @doc "Ressuscita da lixeira."
  def restore_changeset(file) do
    change(file, apagado_em: nil)
  end

  @doc "O proximo rkey (TID) de arquivo, a partir de agora."
  def next_rkey do
    micros = System.os_time(:microsecond)
    clock = rem(:erlang.unique_integer([:positive]), 1024)
    {rkey, _int} = Tid.next(0, micros, clock)
    rkey
  end
end
