defmodule Ypy.KeyStore.Files do
  @moduledoc """
  Stores each Tekoa private key in a file under `Ypy.Layout.keys`.

  Initialization claims the destination exclusively. Explicit rotation writes
  a protected temporary file and atomically replaces the destination.
  """

  @behaviour Ypy.KeyStore

  alias Ypy.Secp256k1

  @enforce_keys [:dir]
  defstruct [:dir]

  @type path :: Path.t()
  @type t :: %__MODULE__{dir: path()}

  @doc "Um Files apontando para o diretorio de chaves."
  @spec new(path()) :: t()
  def new(dir) when is_binary(dir), do: %__MODULE__{dir: dir}

  @impl true
  def generate(_store), do: {:ok, Secp256k1.generate_keypair()}

  @impl true
  def sign(store, tekoa_id, payload) do
    with {:ok, priv} <- load(store, tekoa_id) do
      {:ok, Secp256k1.sign(priv, payload)}
    end
  end

  @impl true
  def fetch_public(store, tekoa_id) do
    with {:ok, priv} <- load(store, tekoa_id) do
      {:ok, Secp256k1.public_from_private(priv)}
    end
  end

  @impl true
  def initialize(store, tekoa_id, {_pub, priv}) do
    target = path(store, tekoa_id)

    case :file.open(target, [:write, :exclusive]) do
      {:ok, device} -> write_private(target, device, priv)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def rotate(store, tekoa_id, {_pub, priv}) do
    replace(store, tekoa_id, priv)
  end

  defp load(store, tekoa_id) do
    case File.read(path(store, tekoa_id)) do
      {:ok, priv} -> {:ok, priv}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp path(%__MODULE__{} = store, tekoa_id), do: Path.join(store.dir, "tekoa-#{tekoa_id}.key")

  defp replace(store, tekoa_id, priv) do
    target = path(store, tekoa_id)
    temp = target <> ".tmp-#{System.unique_integer([:positive])}"

    with {:ok, device} <- :file.open(temp, [:write, :exclusive]),
         :ok <- write_private(temp, device, priv),
         :ok <- File.rename(temp, target) do
      :ok
    else
      {:error, _reason} = error ->
        File.rm(temp)
        error
    end
  end

  defp write_private(path, device, priv) do
    result =
      with :ok <- File.chmod(path, 0o600) do
        :file.write(device, priv)
      end

    close_result = :file.close(device)

    case {result, close_result} do
      {:ok, :ok} ->
        :ok

      {{:error, _reason} = error, _close_result} ->
        File.rm(path)
        error

      {:ok, {:error, reason}} ->
        File.rm(path)
        {:error, reason}
    end
  end
end
