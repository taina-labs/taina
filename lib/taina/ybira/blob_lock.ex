defmodule Taina.Ybira.BlobLock do
  @moduledoc """
  Travessa local (um no) dos blobs, por CID: a secao critica do upload (os
  bytes gravados ANTES de a referencia commitar) e a do GC (a conferencia de
  referencias seguida do apagao) se excluem mutuamente para os MESMOS bytes.

  Sem ela, o GC podia conferir referencias (nenhuma linha ainda), apagar os
  bytes do disco e um upload concorrente dos mesmos bytes commitar em seguida
  a referencia: arquivo vivo sem blob. A graca de uma hora do GC nao fecha
  esta janela (ela cobre so a distancia entre o enfileiramento do CID e a
  rodada do GC); a travessa fecha.

  Uploads de conteudo diferente nao se tocam (a chave e o CID); o que
  compartilha bytes com um blob em expurgo espera a secao critica do GC, que
  e uma conferencia e um `File.rm` no maximo. O GC roda de hora em hora, e
  rapido, e a fila e pequena: a espera e rara e curta. Semantica residual:
  um upload que committou ANTES da rodada reanima o blob (a conferencia acha
  a referencia e a fila so cai); um que commitar DEPOIS do apagao regrava os
  mesmos bytes no mesmo endereco (o `Disk.put_file/2` e idempotente).

  Um GenServer proprio em vez de `:global.trans/2`: em no nao distribuido o
  `:global` nao roda e `set_lock/3` responde true sem travar nada (o no da
  caixa roda sem distribuicao). Monitores limpam a travessa de processo que
  morreu com ela; reentrada com a mesma chave levanta, em vez de travar em
  silencio.
  """

  use GenServer

  @infinity_timeout :infinity

  @doc """
  Roda `fun` com a travessa do CID retida: enquanto `fun` roda, nenhuma
  outra secao critica do mesmo CID roda em paralelo. Devolve o resultado de
  `fun`; a travessa cai em qualquer saida, inclusive excecao.
  """
  @spec run(String.t(), (-> result)) :: result when result: var
  def run(cid, fun) when is_binary(cid) and is_function(fun, 0) do
    case GenServer.call(__MODULE__, {:lock, cid}, @infinity_timeout) do
      :granted ->
        try do
          fun.()
        after
          :ok = GenServer.call(__MODULE__, {:unlock, cid}, @infinity_timeout)
        end

      # Reentrada com a mesma chave travaria em silencio (a fila espera o
      # proprio dono): levanta logo, com a causa na cara.
      {:error, :reentrant} ->
        raise ArgumentError, "Taina.Ybira.BlobLock: reentrada na travessa do CID #{cid}"
    end
  end

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  # O estado e o mapa de travas retidas: `cid => {dono, monitor, fila}`. A
  # fila guarda `{pid, monitor, from}` dos processos esperando a vez, na
  # ordem do pedido (o primeiro da fila e o proximo dono).
  def handle_call({:lock, cid}, {pid, _tag} = from, state) do
    case Map.get(state, cid) do
      nil ->
        mon = Process.monitor(pid)
        {:reply, :granted, Map.put(state, cid, {pid, mon, []})}

      {^pid, _mon, _queue} ->
        {:reply, {:error, :reentrant}, state}

      {owner, owner_mon, queue} ->
        mon = Process.monitor(pid)
        {:noreply, Map.put(state, cid, {owner, owner_mon, queue ++ [{pid, mon, from}]})}
    end
  end

  def handle_call({:unlock, cid}, {pid, _tag}, state) do
    case Map.get(state, cid) do
      {^pid, mon, queue} ->
        Process.demonitor(mon, [:flush])
        {:reply, :ok, grant(cid, queue, Map.delete(state, cid))}

      _trava_alheia_ou_ausente ->
        # Sem a trava (ja solta ou de outro dono): nao ha o que fazer. A saida
        # pelo `after` do dono sempre chega com a trava dele na mao.
        {:reply, :ok, state}
    end
  end

  @impl true
  # Dono ou esperando na fila que morreu: solta a trava (passando a vez) ou
  # tira da fila. Um `DOWN` pode chegar depois de a vez ter passado ao
  # processo: nesse caso ele e o dono da trava e o caminho do dono cuida.
  def handle_info({:DOWN, mon, :process, _pid, _reason}, state) do
    state =
      Enum.reduce(state, state, fn
        {cid, {_pid, ^mon, queue}}, acc -> grant(cid, queue, Map.delete(acc, cid))
        _outra_trava, acc -> acc
      end)

    {:noreply,
     Map.new(state, fn
       {cid, {owner, owner_mon, queue}} ->
         {cid, {owner, owner_mon, Enum.reject(queue, fn {_p, m, _f} -> m == mon end)}}

       outra_trava ->
         outra_trava
     end)}
  end

  # Passa a vez ao primeiro da fila (responde a chamada dele, que espera no
  # `run/2`) ou encerra a trava se a fila acabou.
  defp grant(_cid, [], state), do: state

  defp grant(cid, [{pid, mon, from} | rest], state) do
    GenServer.reply(from, :granted)
    Map.put(state, cid, {pid, mon, rest})
  end
end
