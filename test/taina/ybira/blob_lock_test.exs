defmodule Taina.Ybira.BlobLockTest do
  # A travessa e um GenServer unico da aplicacao (sem estado por teste): cada
  # teste usa CIDs proprios, e o modo compartilhado do sandbox cobre os
  # processos que os testes sobem.
  use Taina.DataCase, async: false

  alias Taina.Ybira.BlobLock

  @tag timeout: 10_000
  test "secoes criticas do mesmo CID se excluem" do
    parent = self()
    cid = unique_cid()

    primeiro =
      Task.async(fn ->
        BlobLock.run(cid, fn ->
          send(parent, :primeiro_entrou)

          receive do
            :pode_sair -> :ok
          end
        end)
      end)

    assert_receive :primeiro_entrou

    # O segundo chega na porta enquanto o primeiro segura a travessa: entra
    # so depois da saida dele.
    segundo =
      Task.async(fn ->
        send(parent, :segundo_na_porta)
        BlobLock.run(cid, fn -> send(parent, :segundo_entrou) end)
      end)

    assert_receive :segundo_na_porta
    refute_receive :segundo_entrou, 100

    send(primeiro.pid, :pode_sair)

    assert_receive :segundo_entrou
    Task.await(primeiro)
    Task.await(segundo)
  end

  @tag timeout: 10_000
  test "CIDs diferentes nao se esperam" do
    parent = self()
    cid_a = unique_cid()
    cid_b = unique_cid()

    um =
      Task.async(fn ->
        BlobLock.run(cid_a, fn ->
          send(parent, :um_entrou)

          receive do
            :pode_sair -> :ok
          end
        end)
      end)

    assert_receive :um_entrou

    dois = Task.async(fn -> BlobLock.run(cid_b, fn -> send(parent, :dois_entrou) end) end)

    assert_receive :dois_entrou, 1_000

    send(um.pid, :pode_sair)
    Task.await(um)
    Task.await(dois)
  end

  test "reentrada com o mesmo CID levanta, em vez de travar em silencio" do
    cid = unique_cid()

    assert_raise ArgumentError, ~r/reentrada/, fn ->
      BlobLock.run(cid, fn -> BlobLock.run(cid, fn -> :nunca end) end)
    end
  end

  @tag timeout: 10_000
  test "dono que morre solta a travessa" do
    parent = self()
    cid = unique_cid()

    dono =
      Task.async(fn ->
        BlobLock.run(cid, fn ->
          send(parent, :entrou)

          receive do
            :espera_eterna -> :ok
          end
        end)
      end)

    assert_receive :entrou
    # O Task e linkado ao teste: solta o enlace antes do kill, para oEXIT
    # nao derrubar o proprio teste (o monitor da travessa continua de pe).
    Process.unlink(dono.pid)
    Process.exit(dono.pid, :kill)

    Task.async(fn -> BlobLock.run(cid, fn -> send(parent, :entrou_depois) end) end)
    assert_receive :entrou_depois, 1_000
  end

  defp unique_cid, do: "b#{System.unique_integer([:positive])}"
end
