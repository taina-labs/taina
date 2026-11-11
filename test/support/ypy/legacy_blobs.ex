defmodule Ypy.BlobStore.Legacy do
  @moduledoc """
  Uma impl do `Ypy.BlobStore` sem o callback opcional `put_file/2`, para
  exercitar o fallback do upload: ler o arquivo na memoria e ir de `put/2`.
  """

  alias Ypy.BlobStore
  alias Ypy.Cid

  @enforce_keys [:inner]
  defstruct [:inner]

  @type binary_data :: binary()
  @type cid :: Cid.t()
  @type path :: Path.t()
  @type t :: %__MODULE__{inner: BlobStore.Disk.t()}

  @doc "Um Legacy que delega os callbacks obrigatorios a um Disk em `root`."
  @spec new(path()) :: t()
  def new(root), do: %__MODULE__{inner: BlobStore.Disk.new(root)}

  @spec put(t(), binary_data()) :: {:ok, cid()} | {:error, term()}
  def put(store, data), do: BlobStore.Disk.put(store.inner, data)

  @spec fetch(t(), cid()) :: {:ok, binary_data()} | {:error, :not_found}
  def fetch(store, cid), do: BlobStore.Disk.fetch(store.inner, cid)

  @spec stat(t(), cid()) :: {:ok, %{size: pos_integer()}} | {:error, :not_found}
  def stat(store, cid), do: BlobStore.Disk.stat(store.inner, cid)

  @spec open(t(), cid()) :: {:ok, BlobStore.path()} | {:error, :not_found | :unsupported}
  def open(store, cid), do: BlobStore.Disk.open(store.inner, cid)

  @spec delete(t(), cid()) :: :ok | {:error, :not_found}
  def delete(store, cid), do: BlobStore.Disk.delete(store.inner, cid)
end
