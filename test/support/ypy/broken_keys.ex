defmodule Ypy.BrokenKeys do
  @moduledoc """
  Um KeyStore cuja assinatura sempre falha: a impl dos testes de resiliencia,
  para provar que uma falha de ledger nao faz falhar a escrita de dado que
  ja commitou. Estrutura, nao Mox.
  """

  @behaviour Ypy.KeyStore

  @enforce_keys [:dir]
  defstruct [:dir]

  @type t :: %__MODULE__{dir: Path.t()}

  def new(dir) when is_binary(dir), do: %__MODULE__{dir: dir}

  @impl true
  def generate(_store), do: {:ok, Ypy.Secp256k1.generate_keypair()}

  @impl true
  def sign(_store, _tekoa_id, _payload), do: {:error, :not_found}

  @impl true
  def fetch_public(_store, _tekoa_id), do: {:error, :not_found}

  @impl true
  def rotate(_store, _tekoa_id, _keypair), do: :ok
end
