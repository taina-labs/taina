defmodule Taina.Blobs do
  @moduledoc """
  O `Ypy.BlobStore` da caixa: bytes em disco, endereçados por CID, sob o
  galho `blobs/` do layout de estado (`Ypy.Layout`).
  """

  alias Ypy.BlobStore.Disk
  alias Ypy.Layout

  @spec new :: Disk.t()
  def new do
    Disk.new(Layout.from_dir(storage_root()).blobs)
  end

  defp storage_root, do: Application.fetch_env!(:taina, :storage_root)
end
