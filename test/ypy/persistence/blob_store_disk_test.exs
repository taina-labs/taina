defmodule Ypy.BlobStore.DiskTest do
  use ExUnit.Case, async: true

  alias Ypy.BlobStore.Disk
  alias Ypy.Cid

  setup do
    root = Path.join(System.tmp_dir!(), "ypy-disk-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    {:ok, store: Disk.new(root), root: root}
  end

  test "put devolve o CID raw e os bytes vao para a arvore", %{store: store, root: root} do
    {:ok, cid} = Disk.put(store, "olá, comunidade")

    assert cid.codec == Cid.raw()

    <<a, b, _rest::binary>> = cid.digest
    shard1 = a |> Integer.to_string(16) |> String.pad_leading(2, "0")
    shard2 = b |> Integer.to_string(16) |> String.pad_leading(2, "0")

    path = Path.join([root, shard1, shard2, Cid.to_string(cid)])
    assert File.read!(path) == "olá, comunidade"
  end

  test "put e idempotente: os mesmos bytes, o mesmo CID", %{store: store} do
    {:ok, cid1} = Disk.put(store, "mesmo dado")
    {:ok, cid2} = Disk.put(store, "mesmo dado")

    assert cid1 == cid2
  end

  test "fetch devolve os bytes", %{store: store} do
    {:ok, cid} = Disk.put(store, <<1, 2, 3>>)
    assert {:ok, <<1, 2, 3>>} == Disk.fetch(store, cid)
  end

  test "fetch de CID ausente e :not_found", %{store: store} do
    cid = Cid.from_data("nunca escrito", Cid.raw())
    assert Disk.fetch(store, cid) == {:error, :not_found}
    assert Disk.stat(store, cid) == {:error, :not_found}
    assert Disk.open(store, cid) == {:error, :not_found}
    assert Disk.delete(store, cid) == {:error, :not_found}
  end

  test "stat devolve o tamanho", %{store: store} do
    {:ok, cid} = Disk.put(store, "12345")
    assert {:ok, %{size: 5}} == Disk.stat(store, cid)
  end

  test "open devolve o caminho que existe", %{store: store} do
    {:ok, cid} = Disk.put(store, "conteudo")
    {:ok, path} = Disk.open(store, cid)
    assert File.exists?(path)
  end

  test "delete tira os bytes", %{store: store} do
    {:ok, cid} = Disk.put(store, "para apagar")
    assert Disk.delete(store, cid) == :ok
    assert Disk.fetch(store, cid) == {:error, :not_found}
  end

  test "put_file transmite o arquivo e cai no mesmo endereco do put", %{store: store, root: root} do
    origem = Path.join(root, "origem.jpg")
    File.write!(origem, "conteudo da foto")

    assert {:ok, cid} = Disk.put_file(store, origem)
    assert cid == Cid.from_data("conteudo da foto", Cid.raw())

    <<a, b, _rest::binary>> = cid.digest
    shard1 = a |> Integer.to_string(16) |> String.pad_leading(2, "0")
    shard2 = b |> Integer.to_string(16) |> String.pad_leading(2, "0")

    assert File.read!(Path.join([root, shard1, shard2, Cid.to_string(cid)])) ==
             "conteudo da foto"

    # O temporario nao sobra: so o galho do CID (e o proprio arquivo).
    assert Path.wildcard(Path.join(root, "tmp-*")) == []
  end

  test "put_file e idempotente: o mesmo arquivo, o mesmo CID", %{store: store, root: root} do
    origem = Path.join(root, "origem")
    File.write!(origem, "mesmo dado")

    {:ok, cid1} = Disk.put_file(store, origem)
    {:ok, cid2} = Disk.put_file(store, origem)

    assert cid1 == cid2
    assert {:ok, "mesmo dado"} == Disk.fetch(store, cid1)
  end

  test "put_file atravessa os blocos: conteudo maior que um bloco sai intacto", %{
    store: store,
    root: root
  } do
    dados = :crypto.strong_rand_bytes(2 * 1024 * 1024 + 7)
    origem = Path.join(root, "grande")
    File.write!(origem, dados)

    assert {:ok, cid} = Disk.put_file(store, origem)
    assert {:ok, ^dados} = Disk.fetch(store, cid)
  end

  test "put_file com origem ausente e erro, sem temporario sobrando", %{
    store: store,
    root: root
  } do
    assert {:error, :enoent} == Disk.put_file(store, Path.join(root, "fantasma"))
    assert File.ls!(root) == []
  end
end
