defmodule Ypy.KeyStore.FilesTest do
  use ExUnit.Case, async: true

  alias Ypy.KeyStore.Files
  alias Ypy.Maraca.Keys
  alias Ypy.Secp256k1

  setup do
    dir =
      Path.join(System.tmp_dir!(), "ypy-keys-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    {:ok, keys: Files.new(dir), dir: dir}
  end

  test "generate mintta um par valido", %{keys: keys} do
    {:ok, {pub, priv}} = Files.generate(keys)
    assert byte_size(pub) == 33
    assert byte_size(priv) == 32
    assert Secp256k1.public_from_private(priv) == pub
  end

  test "rotate reclama o arquivo com exclusao e assina", %{keys: keys, dir: dir} do
    {:ok, {pub, priv}} = Files.generate(keys)

    assert Files.rotate(keys, 1, {pub, priv}) == :ok

    path = Path.join(dir, "tekoa-1.key")
    assert File.read!(path) == priv
    assert Bitwise.band(File.stat!(path).mode, 0o777) == 0o600

    assert {:ok, signature} = Files.sign(keys, 1, "corpo")
    assert byte_size(signature) == 64
    assert Keys.verify(pub, signature, "corpo")
  end

  test "sign e fetch_public sem chave respondem :not_found", %{keys: keys} do
    assert Files.sign(keys, 99, "corpo") == {:error, :not_found}
    assert Files.fetch_public(keys, 99) == {:error, :not_found}
  end

  test "fetch_public deriva a publica da privada guardada", %{keys: keys} do
    {:ok, {pub, priv}} = Files.generate(keys)
    :ok = Files.rotate(keys, 7, {pub, priv})

    assert {:ok, pub} == Files.fetch_public(keys, 7)
  end

  test "rotate sobre arquivo existente substitui atomicamente", %{keys: keys, dir: dir} do
    {:ok, {pub1, priv1}} = Files.generate(keys)
    {:ok, {pub2, priv2}} = Files.generate(keys)

    :ok = Files.rotate(keys, 3, {pub1, priv1})
    :ok = Files.rotate(keys, 3, {pub2, priv2})

    assert File.read!(Path.join(dir, "tekoa-3.key")) == priv2
    assert {:ok, ^pub2} = Files.fetch_public(keys, 3)
  end

  test "rotate deixa de reclamar exclusivamente quando o arquivo ja existe, sem sobrar temporario",
       %{
         keys: keys,
         dir: dir
       } do
    {:ok, {pub, priv}} = Files.generate(keys)
    :ok = Files.rotate(keys, 4, {pub, priv})
    {:ok, {pub_nova, priv_nova}} = Files.generate(keys)

    :ok = Files.rotate(keys, 4, {pub_nova, priv_nova})

    assert File.read!(Path.join(dir, "tekoa-4.key")) == priv_nova
    assert dir |> Path.join("tekoa-4.key.tmp-123") |> File.exists?() == false
    assert Enum.empty?(Path.wildcard(Path.join(dir, "*.tmp-*")))
  end
end
