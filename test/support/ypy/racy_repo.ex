defmodule Ypy.RacyRepo do
  @moduledoc """
  O repo que simula o escritor concorrente do mural (RFC_006 secao 8): o
  teste arma o conflito e a proxima insercao da cadeia encontra a sequencia
  tomada por um append concorrente verdadeiro, conflita no indice unico e a
  transacao inteira (dado mais append) precisa recomecar.

  Deterministico: nada de sono nem corrida de relogio. `arm/4` conflita uma
  vez e `arm_always/4` conflita em toda insercao da cadeia (para esgotar as
  tres tentativas e ver {:error, :chain_conflict}).
  """

  alias Ypy.Mural.Store
  alias Ypy.TestRepo

  @armed :racy_repo_armed
  @barrier_key {__MODULE__, :concurrent_commit_owner}

  def arm(keys, tekoa_id, tipo, payload) do
    Process.put(@armed, {:once, keys, tekoa_id, tipo, payload})
  end

  def arm_always(keys, tekoa_id, tipo, payload) do
    Process.put(@armed, {:always, keys, tekoa_id, tipo, payload})
  end

  def arm_concurrent_commit(owner), do: :persistent_term.put(@barrier_key, owner)

  def disarm do
    Process.delete(@armed)
    :persistent_term.erase(@barrier_key)
  end

  def one(query, opts \\ []), do: TestRepo.one(query, opts)
  def all(query, opts \\ []), do: TestRepo.all(query, opts)

  def insert(changeset, opts \\ [])

  # So a insercao da cadeia e armada: o dado da transacao sob teste passa
  # reto, e o rival toma a sequencia entre a leitura da cabeca e o insert.
  def insert(%Ecto.Changeset{data: %Ypy.Mural.Entry{}} = changeset, opts) do
    case Process.get(@armed) do
      nil ->
        TestRepo.insert(changeset, opts)

      {mode, keys, tekoa_id, tipo, payload} ->
        case mode do
          :once -> disarm()
          :always -> nil
        end

        _ = Store.append(TestRepo, keys, tekoa_id, tipo, payload)
        TestRepo.insert(changeset, opts)
    end
  end

  def insert(changeset, opts), do: TestRepo.insert(changeset, opts)

  def update(changeset, opts \\ []), do: TestRepo.update(changeset, opts)

  def transaction(fun, opts \\ []) do
    await_barrier(:transaction)
    Process.put(:racy_repo_in_transaction, true)

    try do
      TestRepo.transaction(fun, opts)
    after
      Process.delete(:racy_repo_in_transaction)
    end
  end

  def rollback(value), do: TestRepo.rollback(value)
  def update_all(query, updates), do: TestRepo.update_all(query, updates)

  def aggregate(query, aggregate, field \\ nil, opts \\ []) do
    if not Process.get(:racy_repo_in_transaction, false), do: await_barrier(:count)

    if is_nil(field) do
      TestRepo.aggregate(query, aggregate, opts)
    else
      TestRepo.aggregate(query, aggregate, field, opts)
    end
  end

  def reload(struct, opts \\ []), do: TestRepo.reload(struct, opts)

  defp await_barrier(phase) do
    case :persistent_term.get(@barrier_key, nil) do
      nil ->
        :ok

      owner ->
        send(owner, {:racy_repo_waiting, phase, self()})

        receive do
          {:racy_repo_continue, ^phase} -> :ok
        end
    end
  end
end
