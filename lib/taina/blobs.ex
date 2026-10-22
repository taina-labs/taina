defmodule Taina.Blobs do
  @moduledoc """
  O `Ypy.BlobStore` da caixa: bytes em disco, endereçados por CID, sob o
  galho `blobs/` do layout de estado (`Ypy.Layout`).
  """

  alias Ypy.BlobStore.Disk
  alias Ypy.Layout

  @spec new :: Disk.t()
  def new do
    root = Layout.from_dir(storage_root()).blobs

    # O kernel 0.2 transmite o upload (`Disk.put_file/2`): o temporário nasce
    # direto na raiz dos blobs, que então precisa existir ANTES (o `put/2` de
    # antes a criava de carona no mkdir do caminho do blob).
    File.mkdir_p!(root)

    Disk.new(root)
  end

  defp storage_root, do: Application.fetch_env!(:taina, :storage_root)
end
