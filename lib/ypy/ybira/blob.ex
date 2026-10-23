defmodule Ypy.Ybira.Blob do
  @moduledoc """
  A existencia de um blob na Tekoa: os bytes moram no `Ypy.BlobStore` pelo
  CID; a linha e o registro de que a Tekoa os tem, dedup por conteudo
  (uploads iguais caem no mesmo CID e na mesma linha). Contagem de
  referencia e expurgo sao nao-objetivos do kernel (RFC_006 secao 15).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Tekoa

  @type t :: %__MODULE__{
          id: integer() | nil,
          cid: String.t() | nil,
          tamanho: integer() | nil,
          hash: String.t() | nil,
          tekoa_id: integer() | nil,
          inserted_at: DateTime.t() | nil
        }

  schema "ybira_blobs" do
    field(:cid, :string)
    field(:tamanho, :integer)
    field(:hash, :string)

    belongs_to(:tekoa, Tekoa)

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(blob, attrs) do
    blob
    |> cast(attrs, [:cid, :tamanho, :hash, :tekoa_id])
    |> validate_required([:cid, :tamanho, :hash, :tekoa_id])
    |> unique_constraint(:cid, name: :ybira_blobs_tekoa_id_cid_index)
  end
end
