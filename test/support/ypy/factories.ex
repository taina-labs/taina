defmodule Ypy.Factories do
  @moduledoc """
  Gente, Tekoa e efeitos de referencia para os testes de persistencia: a
  Tekoa nasce com chave (`KeyStore.Files` + linha `TekoaKey`), os avas nascem
  pelo changeset do kernel e os efeitos rodam sobre diretorios temporarios.
  """

  alias Ypy.BlobStore
  alias Ypy.KeyStore
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Store
  alias Ypy.Maraca.Tekoa
  alias Ypy.Maraca.TekoaKey
  alias Ypy.Scope

  @doc "Uma Tekoa com chave ativa; devolve {tekoa, keys} do KeyStore dela."
  def nova_tekoa(repo, attrs \\ []) do
    attrs =
      Keyword.merge(
        [name: "Tekoa de Teste", domain: "tekoa.test", storage_quota_bytes: nil],
        attrs
      )

    {:ok, tekoa} = repo.insert(Tekoa.changeset(%Tekoa{}, Map.new(attrs)))

    keys = KeyStore.Files.new(dir_temporario("keys"))
    {:ok, keypair} = KeyStore.Files.generate(keys)
    :ok = KeyStore.Files.rotate(keys, tekoa.id, keypair)
    {pub, _priv} = keypair

    {:ok, _} =
      Store.insert(
        repo,
        TekoaKey.changeset(%TekoaKey{}, %{
          tekoa_id: tekoa.id,
          pub: pub,
          multibase: TekoaKey.multibase(pub)
        })
      )

    {tekoa, keys}
  end

  @doc "Um morador ativo da Tekoa; attrs vao direto ao changeset."
  def novo_ava(repo, tekoa, attrs \\ []) do
    attrs =
      Keyword.merge(
        [
          username: "morador#{:erlang.unique_integer([:positive])}",
          papel: :morador
        ],
        attrs
      )

    # tekoa_id e programatico (fora do cast): vai no struct, nunca no attrs.
    # A ativacao e direta (os testes nao pagam bcrypt por factory); o aceite
    # de convite com senha tem teste proprio.
    {:ok, ava} = repo.insert(Ava.changeset(%Ava{tekoa_id: tekoa.id}, Map.new(attrs)))

    ativado =
      Ecto.Changeset.change(ava, activated_at: DateTime.truncate(DateTime.utc_now(), :second))

    {:ok, ava} = repo.update(ativado)

    {:ok, repo.reload!(ava)}
  end

  @doc "O escopo de quem age: o ava dentro da Tekoa."
  def scope(ava, tekoa), do: %Scope{ava: ava, tekoa: tekoa}

  @doc "Um BlobStore.Disk sobre diretorio temporario novo."
  def blobs do
    BlobStore.Disk.new(dir_temporario("blobs"))
  end

  @doc "Um diretorio temporario unico sob o prefixo dado."
  def dir_temporario(prefixo) do
    dir = Path.join(System.tmp_dir!(), "ypy-#{prefixo}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  @doc "Os bytes de um arquivo temporario; devolve {path, data}."
  def arquivo(dados) when is_binary(dados) do
    path = Path.join(dir_temporario("upload"), "arquivo")
    File.write!(path, dados)
    {path, dados}
  end
end
