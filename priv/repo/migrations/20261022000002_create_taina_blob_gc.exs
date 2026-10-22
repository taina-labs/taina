defmodule Taina.Repo.Migrations.CreateTainaBlobGc do
  @moduledoc """
  A fila do GC diferido de blobs (revisão 0.1.0, item 1c): o expurgo da
  lixeira enfileira o CID em vez de apagar os bytes na hora, fechando a
  janela em que um upload concorrente (dedup) pode commitar o mesmo blob.
  O CID é único na fila (um blob, uma entrada; enfileirar de novo é no-op).
  """

  use Ecto.Migration

  def change do
    create table(:taina_blob_gc) do
      add :blob_cid, :string, null: false
      add :enqueued_at, :utc_datetime, null: false
    end

    create unique_index(:taina_blob_gc, [:blob_cid])
  end
end
