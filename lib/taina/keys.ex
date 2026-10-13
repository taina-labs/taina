defmodule Taina.Keys do
  @moduledoc """
  O `Ypy.KeyStore` da caixa: a chave privada da Tekoa em arquivo, sob o galho
  `keys/` do layout de estado (`Ypy.Layout`), mais a cunhagem da chave
  (gera o par, guarda o privado no `KeyStore`, registra a publica na
  Tekoa ativa). Idempotente: Tekoa que ja tem chave ativa nao cunha de novo.
  """

  import Ecto.Query

  alias Taina.Repo
  alias Ypy.KeyStore.Files
  alias Ypy.Layout
  alias Ypy.Maraca.Store, as: KernelStore
  alias Ypy.Maraca.TekoaKey

  @spec new :: Files.t()
  def new do
    dir = Layout.from_dir(storage_root()).keys
    File.mkdir_p!(dir)
    Files.new(dir)
  end

  @doc "Cunha a chave ativa da Tekoa quando ela nao tem nenhuma."
  @spec mint(Ecto.Repo.t(), integer()) :: :ok | {:error, term()}
  def mint(repo \\ Repo, tekoa_id) do
    # Consulta de sistema: a cunhagem acontece no bootstrap e nas fixtures,
    # antes de haver contexto de Tekoa.
    query = from(k in TekoaKey, where: k.tekoa_id == ^tekoa_id and is_nil(k.aposentada_em))

    if repo.one(query, skip_tekoa_id: true) do
      :ok
    else
      files = new()

      with {:ok, {pub, _priv} = keypair} <- Files.generate(files),
           :ok <- Files.rotate(files, tekoa_id, keypair),
           {:ok, _key} <-
             KernelStore.insert(
               repo,
               TekoaKey.changeset(%TekoaKey{}, %{
                 tekoa_id: tekoa_id,
                 pub: pub,
                 multibase: TekoaKey.multibase(pub)
               })
             ) do
        :ok
      end
    end
  end

  defp storage_root, do: Application.fetch_env!(:taina, :storage_root)
end
