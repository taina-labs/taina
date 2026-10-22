defmodule Taina.Ybira.BlobGc do
  @moduledoc """
  A fila do GC diferido de blobs (revisão 0.1.0, item 1c): o CID dos bytes de
  um arquivo expurgado e o instante do enfileiramento.

  O expurgo da lixeira enfileira em vez de apagar os bytes na hora: entre a
  conferência de referências e o apagão, um upload concorrente pode commitar
  um arquivo que compartilha o mesmo CID (dedup), e o expurgo apagaria bytes
  de arquivo vivo. O worker `Taina.Ybira.Workers.BlobGc` processa a fila mais
  velha que a graça de uma hora: sem `ybira_files` referenciando o CID, os
  bytes saem do disco e a fila cai; com referência, o blob voltou a viver e
  só a fila cai.

  Tabela de sistema (sem Tekoa): a fila é da caixa, não de uma comunidade.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          blob_cid: String.t() | nil,
          enqueued_at: DateTime.t() | nil
        }

  schema "taina_blob_gc" do
    field :blob_cid, :string
    field :enqueued_at, :utc_datetime
  end
end
