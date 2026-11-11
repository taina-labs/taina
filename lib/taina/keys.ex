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
  alias Ypy.Maraca.TekoaKey

  @type files :: Files.t()
  @type repo :: Ecto.Repo.t()
  @type tekoa_id :: integer()

  @spec new :: files()
  def new do
    dir = Layout.from_dir(storage_root()).keys
    File.mkdir_p!(dir)
    Files.new(dir)
  end

  @doc "Cunha a chave ativa da Tekoa quando ela nao tem nenhuma."
  @spec mint(repo(), tekoa_id()) :: :ok | {:error, term()}
  def mint(repo \\ Repo, tekoa_id) do
    # Consulta de sistema: a cunhagem acontece no bootstrap e nas fixtures,
    # antes de haver contexto de Tekoa.
    query = from(k in TekoaKey, where: k.tekoa_id == ^tekoa_id and is_nil(k.aposentada_em))

    if repo.one(query, skip_tekoa_id: true) do
      :ok
    else
      files = new()

      with {:ok, {_pub, _priv} = keypair} <- Files.generate(files),
           {:ok, pub} <- initialize_or_fetch(files, tekoa_id, keypair),
           {:ok, _key} <-
             repo.insert(
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

  defp initialize_or_fetch(files, tekoa_id, {pub, _priv} = keypair) do
    case Files.initialize(files, tekoa_id, keypair) do
      :ok -> {:ok, pub}
      {:error, :eexist} -> Files.fetch_public(files, tekoa_id)
      {:error, _reason} = error -> error
    end
  end

  defp storage_root, do: Application.fetch_env!(:taina, :storage_root)
end
