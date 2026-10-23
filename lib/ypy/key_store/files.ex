defmodule Ypy.KeyStore.Files do
  @moduledoc """
  A chave privada da Tekoa em um arquivo sob o diretorio de chaves
  (`Ypy.Layout.keys`), uma por Tekoa, no mesmo risco do Pesque: o arquivo nasce
  com exclusao (`O_EXCL`) para que duas inicializacoes em corrida nao caiam
  uma sobre a outra, e o `chmod` vem depois do create porque o open do Erlang
  ignora modo de criacao.
  """

  @behaviour Ypy.KeyStore

  alias Ypy.Secp256k1

  @enforce_keys [:dir]
  defstruct [:dir]

  @type t :: %__MODULE__{dir: Path.t()}

  @doc "Um Files apontando para o diretorio de chaves."
  @spec new(Path.t()) :: t()
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
  def rotate(store, tekoa_id, {_pub, priv}) do
    case :file.open(path(store, tekoa_id), [:write, :exclusive]) do
      {:ok, device} ->
        with :ok <- :file.write(device, priv),
             :ok <- :file.close(device) do
          File.chmod(path(store, tekoa_id), 0o600)
        end

      {:error, :eexist} ->
        replace(store, tekoa_id, priv)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A substituicao e atomica via temporario + rename: um leitor (sign em
  # outro processo) ve a chave velha inteira ou a nova inteira, nunca metade.
  defp replace(store, tekoa_id, priv) do
    target = path(store, tekoa_id)
    temp = target <> ".tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temp, priv),
         :ok <- File.chmod(temp, 0o600) do
      File.rename(temp, target)
    end
  end

  defp load(store, tekoa_id) do
    case File.read(path(store, tekoa_id)) do
      {:ok, priv} -> {:ok, priv}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp path(%__MODULE__{} = store, tekoa_id), do: Path.join(store.dir, "tekoa-#{tekoa_id}.key")
end
