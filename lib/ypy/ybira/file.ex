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
    field(:apagado_em, :utc_datetime)
    field(:blob_cid, :string)
    field(:cid, :string)
    belongs_to(:dono, Ava)
    field(:effective_at, :utc_datetime)
    belongs_to(:folder, Folder)
    field(:hash, :string)
    field(:mime, :string)
    field(:nome, :string)
    field(:rkey, :string)
    field(:tamanho, :integer)
    belongs_to(:tekoa, Tekoa)
    field(:zona, Ecto.Enum, values: [:casa, :praca], default: :casa)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria o arquivo. `rkey` e `cid` (do envelope) sao programaticos."
  def changeset(file, attrs) do
    file
    |> cast(attrs, [
      :blob_cid,
      :cid,
      :dono_id,
      :effective_at,
      :folder_id,
      :hash,
      :mime,
      :nome,
      :rkey,
      :tamanho,
      :tekoa_id,
      :zona
    ])
    |> validate_required([
      :blob_cid,
      :cid,
      :dono_id,
      :hash,
      :mime,
      :nome,
      :rkey,
      :tamanho,
      :tekoa_id
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
    |> cast(attrs, [:cid, :folder_id, :nome])
    |> validate_required([:cid, :nome])
    |> validate_length(:nome, min: 1, max: 255)
  end
end
