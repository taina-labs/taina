defmodule Ypy.Mural.PersistenceTest do
  use Ypy.PersistenceCase, async: false

  import Ecto.Query
  import Ypy.Factories

  alias Ypy.KeyStore.Files
  alias Ypy.Maraca.TekoaKey
  alias Ypy.Mural
  alias Ypy.Mural.Store
  alias Ypy.RacyRepo
  alias Ypy.Secp256k1
  alias Ypy.Ybira.Folder

  setup do
    {tekoa, keys} = nova_tekoa(TestRepo)
    %{tekoa: tekoa, keys: keys}
  end

  test "o append encadeia do genesis: prev nil, seq 1, e a assinatura confere", %{
    tekoa: tekoa,
    keys: keys
  } do
    {:ok, entrada} = Store.append(TestRepo, keys, tekoa.id, "publicar", %{"rkey" => "rk1"})

    assert entrada.seq == 1
    assert entrada.prev == nil
    assert entrada.tipo == "publicar"
    assert entrada.payload == %{"tipo" => "publicar", "rkey" => "rk1"}

    assert Mural.verify_entry(tekoa_pub(TestRepo, tekoa.id), to_entry(entrada)) == :ok
  end

  test "a cadeia cresce encadeada e verifica inteira", %{tekoa: tekoa, keys: keys} do
    {:ok, _} = Store.append(TestRepo, keys, tekoa.id, "publicar", %{"rkey" => "rk1"})
    {:ok, _} = Store.append(TestRepo, keys, tekoa.id, "concessao", %{"rkey" => "rk2"})
    {:ok, ultima} = Store.append(TestRepo, keys, tekoa.id, "put", %{"rkey" => "rk3"})

    assert ultima.seq == 3
    assert Enum.map(Store.cadeia(TestRepo, tekoa.id), & &1.seq) == [1, 2, 3]
    assert Store.verificar_cadeia(TestRepo, tekoa.id) == :ok
  end

  test "the chain verifies entries signed before and after rotation", %{
    tekoa: tekoa,
    keys: keys
  } do
    {:ok, primeira} = Store.append(TestRepo, keys, tekoa.id, "put", %{"rkey" => "antes"})
    chave_antiga = Ypy.Maraca.Store.chave_ativa(TestRepo, tekoa.id)
    agora = DateTime.truncate(DateTime.utc_now(), :second)

    {:ok, {pub_nova, priv_nova} = par_novo} = Files.generate(keys)
    :ok = Files.rotate(keys, tekoa.id, par_novo)

    chave_antiga
    |> TekoaKey.retire_changeset(agora)
    |> TestRepo.update!()

    {:ok, _chave_nova} =
      TestRepo.insert(
        TekoaKey.changeset(%TekoaKey{}, %{
          tekoa_id: tekoa.id,
          pub: pub_nova,
          multibase: TekoaKey.multibase(pub_nova)
        })
      )

    {:ok, segunda} = Store.append(TestRepo, keys, tekoa.id, "put", %{"rkey" => "depois"})

    assert primeira.signing_key == chave_antiga.pub
    assert segunda.signing_key == pub_nova
    assert Store.verificar_cadeia(TestRepo, tekoa.id) == :ok

    TestRepo.update!(Ecto.Changeset.change(segunda, signature: :crypto.strong_rand_bytes(64)))
    assert Store.verificar_cadeia(TestRepo, tekoa.id) == {:error, {1, :bad_signature}}

    assert Secp256k1.public_from_private(priv_nova) == pub_nova
  end

  test "conflito de sequencia sob escritor concorrente: a transacao inteira recomeca e vence", %{
    tekoa: tekoa,
    keys: keys
  } do
    {:ok, dono} = novo_ava(TestRepo, tekoa)
    {:ok, primeira} = Store.append(TestRepo, keys, tekoa.id, "put", %{"rkey" => "rk1"})

    # O proximo escritor encontra a seq tomada por um append concorrente
    # verdadeiro: a transacao inteira (dado mais cadeia) recomeca da cabeca.
    RacyRepo.arm(keys, tekoa.id, "concessao", %{"rkey" => "rival"})

    {:ok, _pasta} = escrever_com_cadeia(RacyRepo, keys, tekoa, dono)

    RacyRepo.disarm()

    # O dado rodou duas vezes porque a primeira transacao rolagou inteira
    # com o append que conflitou; o que ficou e o dado da segunda, com a
    # entrada encadeada.
    assert Process.get(:escritas) == 2
    assert dado_contado(tekoa) == 1

    assert Store.verificar_cadeia(TestRepo, tekoa.id) == :ok
    assert Store.head(TestRepo, tekoa.id).seq == 2
    assert Store.entrada(TestRepo, tekoa.id, 2).prev == primeira.cid
  end

  test "conflito em toda tentativa: tres transacoes inteiras e :chain_conflict", %{
    tekoa: tekoa,
    keys: keys
  } do
    {:ok, dono} = novo_ava(TestRepo, tekoa)
    {:ok, _} = Store.append(TestRepo, keys, tekoa.id, "put", %{"rkey" => "rk1"})

    RacyRepo.arm_always(keys, tekoa.id, "rival", %{"rkey" => "rival"})

    assert escrever_com_cadeia(RacyRepo, keys, tekoa, dono) == {:error, :chain_conflict}

    RacyRepo.disarm()

    # Tres transacoes inteiras rodaram e nenhuma ficou: sem dado, sem entrada.
    assert Process.get(:escritas) == 3
    assert dado_contado(tekoa) == 0

    assert Store.verificar_cadeia(TestRepo, tekoa.id) == :ok
    assert Store.head(TestRepo, tekoa.id).seq == 1
  end

  test "sem chave para assinar, o append responde o erro do KeyStore", %{tekoa: tekoa} do
    sem_chave = Files.new(Ypy.Factories.dir_temporario("keys-vazias"))

    assert Store.append(TestRepo, sem_chave, tekoa.id, "put", %{"rkey" => "rk1"}) ==
             {:error, :not_found}

    assert Store.cadeia(TestRepo, tekoa.id) == []
  end

  test "a projecao filtra por tipo e pagina por cursor de seq", %{tekoa: tekoa, keys: keys} do
    {:ok, e1} = Store.append(TestRepo, keys, tekoa.id, "publicar", %{"rkey" => "rk1"})
    {:ok, _} = Store.append(TestRepo, keys, tekoa.id, "concessao", %{"rkey" => "rk2"})
    {:ok, e3} = Store.append(TestRepo, keys, tekoa.id, "publicar", %{"rkey" => "rk3"})

    publica = Store.entradas(TestRepo, tekoa.id, tipo: "publicar")
    assert Enum.map(publica, & &1.seq) == [e3.seq, e1.seq]

    assert Enum.map(Store.entradas(TestRepo, tekoa.id), & &1.seq) == [3, 2, 1]

    do_meio = Store.entradas(TestRepo, tekoa.id, cursor: e3.seq)
    assert Enum.map(do_meio, & &1.seq) == [2, e1.seq]

    assert Store.entrada(TestRepo, tekoa.id, 2).tipo == "concessao"
    assert Store.entrada(TestRepo, tekoa.id, 9) == nil
  end

  test "verificar_cadeia sem chave ativa responde :not_found", %{tekoa: tekoa, keys: keys} do
    {:ok, _} = Store.append(TestRepo, keys, tekoa.id, "put", %{"rkey" => "rk1"})

    _ =
      TestRepo
      |> Ypy.Maraca.Store.chave_ativa(tekoa.id)
      |> TekoaKey.retire_changeset(DateTime.truncate(DateTime.utc_now(), :second))
      |> TestRepo.update!()

    assert Store.verificar_cadeia(TestRepo, tekoa.id) == {:error, :not_found}
  end

  defp tekoa_pub(repo, tekoa_id) do
    %TekoaKey{pub: pub} = Ypy.Maraca.Store.chave_ativa(repo, tekoa_id)
    pub
  end

  # A escrita de dado que corre com a cadeia: uma pasta, contada cada vez que
  # a transacao a executa (o retry reexecuta a transacao inteira).
  defp escrever_com_cadeia(repo, keys, tekoa, dono) do
    Store.commit(repo, keys, tekoa.id, "publicar", %{"rkey" => "rk2"}, fn ->
      Process.put(:escritas, Process.get(:escritas, 0) + 1)

      repo.insert(
        Folder.changeset(%Folder{}, %{
          tekoa_id: tekoa.id,
          dono_id: dono.id,
          rkey: "rrrrrrrrrrrrr",
          cid: "cid-do-dado",
          nome: "pasta do dado"
        })
      )
    end)
  end

  defp dado_contado(tekoa) do
    TestRepo.aggregate(from(f in Folder, where: f.tekoa_id == ^tekoa.id), :count)
  end

  defp to_entry(%Ypy.Mural.Entry{} = row) do
    %{
      "seq" => row.seq,
      "prev" => row.prev && Ypy.Cid.parse(row.prev),
      "payload" => row.payload,
      "signature" => row.signature,
      "signing_key" => row.signing_key
    }
  end
end
