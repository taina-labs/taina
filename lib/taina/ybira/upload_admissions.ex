defmodule Taina.Ybira.UploadAdmissions do
  @moduledoc """
  Serializes upload capacity decisions while allowing staged copies to run in parallel.
  """

  use GenServer

  @max_active_upload_rows 20
  @pending_byte_budget_multiplier 2
  @disk_clear_headroom_bytes 64 * 1024 * 1024
  @persisted_reservations {__MODULE__, :reservations}

  @type active_upload :: %{
          required(:public_id) => String.t(),
          required(:size) => non_neg_integer(),
          required(:staging_key) => String.t()
        }
  @type snapshot :: %{
          required(:storage_used_bytes) => non_neg_integer(),
          required(:storage_quota_bytes) => non_neg_integer() | nil,
          required(:active_uploads) => [active_upload()],
          required(:staging_entries) => [staging_entry()],
          required(:storage_root) => String.t(),
          required(:disk_free_bytes) => non_neg_integer() | :unavailable,
          required(:max_blob_size) => pos_integer()
        }
  @type staging_entry :: %{required(:name) => String.t(), required(:size) => non_neg_integer()}
  @type text :: String.t()

  @doc false
  def max_active_rows, do: @max_active_upload_rows

  @doc false
  def pending_byte_budget(max_blob_size), do: @pending_byte_budget_multiplier * max_blob_size

  @doc false
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc false
  @spec with_reservation(
          pos_integer(),
          text(),
          pos_integer(),
          (-> {:ok, snapshot()} | {:error, term()}),
          (-> term())
        ) :: term()
  def with_reservation(tekoa_id, public_id, incoming_size, snapshot_fun, operation_fun)
      when is_integer(tekoa_id) and tekoa_id > 0 and is_binary(public_id) and is_integer(incoming_size) and
             incoming_size > 0 and is_function(snapshot_fun, 0) and is_function(operation_fun, 0) do
    tekoa_id
    |> reserve(public_id, incoming_size, snapshot_fun)
    |> run_or_reject(operation_fun)
  end

  defp run_or_reject({:ok, token}, operation_fun), do: run_reserved_operation(token, operation_fun)

  defp run_or_reject({:error, _reason} = error, _operation_fun), do: error
  defp run_or_reject(:aborted, _operation_fun), do: {:error, :admission_unavailable}

  defp reserve(tekoa_id, public_id, incoming_size, snapshot_fun) do
    case GenServer.call(__MODULE__, :begin_decision, :infinity) do
      {:ok, decision_ref} ->
        decide_with_snapshot(
          decision_ref,
          tekoa_id,
          public_id,
          incoming_size,
          snapshot_fun
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp decide_with_snapshot(decision_ref, tekoa_id, public_id, incoming_size, snapshot_fun) do
    with {:ok, snapshot} <- snapshot_fun.() do
      GenServer.call(
        __MODULE__,
        {:finish_decision, decision_ref, tekoa_id, public_id, incoming_size, snapshot},
        :infinity
      )
    end
  after
    GenServer.call(__MODULE__, {:abort_decision, decision_ref}, :infinity)
  end

  defp run_reserved_operation(token, operation_fun) do
    operation_fun.()
  after
    release(token)
  end

  @impl GenServer
  def init(:ok) do
    reservations = recover_reservations()
    persist_reservations(reservations)

    {:ok,
     %{
       reservations: reservations,
       decision: nil,
       waiters: :queue.new(),
       pending_releases: []
     }}
  end

  @impl GenServer
  def handle_call(:begin_decision, from, %{decision: nil} = state) do
    decision = new_decision(from)
    {:reply, {:ok, decision.ref}, %{state | decision: decision}}
  end

  def handle_call(:begin_decision, from, state) do
    waiter = new_waiter(from)
    {:noreply, %{state | waiters: :queue.in(waiter, state.waiters)}}
  end

  def handle_call({:finish_decision, ref, tekoa_id, public_id, size, snapshot}, {owner, _tag}, state) do
    case state.decision do
      %{ref: ^ref, owner: ^owner} = decision ->
        finish_decision(decision, tekoa_id, public_id, size, snapshot, state)

      _other ->
        {:reply, {:error, :admission_unavailable}, state}
    end
  end

  def handle_call({:abort_decision, ref}, {owner, _tag}, state) do
    case state.decision do
      %{ref: ^ref, owner: ^owner, monitor: monitor} ->
        Process.demonitor(monitor, [:flush])

        state =
          state
          |> Map.put(:decision, nil)
          |> apply_pending_releases()
          |> grant_next_decision()

        {:reply, :ok, state}

      _other ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:release, token}, from, state) do
    cond do
      not Map.has_key?(state.reservations, token) ->
        {:reply, :ok, state}

      not is_nil(state.decision) ->
        {:noreply, %{state | pending_releases: [{from, token} | state.pending_releases]}}

      true ->
        {:reply, :ok, release_reservation(token, state)}
    end
  end

  defp finish_decision(decision, tekoa_id, public_id, size, snapshot, state) do
    token = make_ref()

    case admission_decision(snapshot, state.reservations, tekoa_id, size) do
      :ok ->
        reservation = %{
          tekoa_id: tekoa_id,
          public_id: public_id,
          size: size,
          storage_root: snapshot.storage_root,
          owner: decision.owner,
          monitor: decision.monitor,
          owner_alive?: true
        }

        reservations =
          state.reservations
          |> prune_reservations()
          |> Map.put(token, reservation)

        persist_reservations(reservations)

        next_state =
          state
          |> Map.merge(%{reservations: reservations, decision: nil})
          |> apply_pending_releases()
          |> grant_next_decision()

        {:reply, {:ok, token}, next_state}

      {:error, reason} ->
        Process.demonitor(decision.monitor, [:flush])
        reservations = prune_reservations(state.reservations)
        persist_reservations(reservations)

        next_state =
          state
          |> Map.merge(%{reservations: reservations, decision: nil})
          |> apply_pending_releases()
          |> grant_next_decision()

        {:reply, {:error, reason}, next_state}
    end
  end

  defp new_decision({owner, _tag}) do
    %{ref: make_ref(), owner: owner, monitor: Process.monitor(owner)}
  end

  defp new_waiter({owner, _tag} = from) do
    %{
      from: from,
      owner: owner,
      ref: make_ref(),
      monitor: Process.monitor(owner)
    }
  end

  defp grant_next_decision(%{decision: nil} = state) do
    case :queue.out(state.waiters) do
      {{:value, waiter}, remaining} ->
        if Process.alive?(waiter.owner) do
          decision = %{ref: waiter.ref, owner: waiter.owner, monitor: waiter.monitor}
          GenServer.reply(waiter.from, {:ok, decision.ref})
          %{state | decision: decision, waiters: remaining}
        else
          Process.demonitor(waiter.monitor, [:flush])
          grant_next_decision(%{state | waiters: remaining})
        end

      {:empty, _queue} ->
        state
    end
  end

  defp grant_next_decision(state), do: state

  defp apply_pending_releases(%{pending_releases: pending} = state) do
    pending
    |> Enum.reverse()
    |> Enum.reduce(%{state | pending_releases: []}, fn {from, token}, acc ->
      GenServer.reply(from, :ok)
      release_reservation(token, acc)
    end)
  end

  defp release_reservation(token, state) do
    case Map.pop(state.reservations, token) do
      {nil, reservations} ->
        %{state | reservations: reservations}

      {%{monitor: monitor}, reservations} ->
        if monitor, do: Process.demonitor(monitor, [:flush])
        persist_reservations(reservations)
        %{state | reservations: reservations}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, monitor, :process, _owner, _reason}, state) do
    case state.decision do
      %{monitor: ^monitor} ->
        next_state =
          state
          |> Map.put(:decision, nil)
          |> apply_pending_releases()
          |> grant_next_decision()

        {:noreply, next_state}

      _other ->
        handle_down_reservation_or_waiter(monitor, state)
    end
  end

  defp handle_down_reservation_or_waiter(monitor, state) do
    waiters =
      state.waiters
      |> :queue.to_list()
      |> Enum.reject(&(&1.monitor == monitor))
      |> :queue.from_list()

    case Enum.find(state.reservations, fn {_token, reservation} -> reservation.monitor == monitor end) do
      {token, _reservation} when is_nil(state.decision) ->
        {:noreply, release_reservation(token, %{state | waiters: waiters})}

      {token, reservation} ->
        updated = %{reservation | monitor: nil, owner_alive?: false}
        reservations = Map.put(state.reservations, token, updated)
        persist_reservations(reservations)
        {:noreply, %{state | reservations: reservations, waiters: waiters}}

      nil ->
        {:noreply, %{state | waiters: waiters}}
    end
  end

  defp recover_reservations do
    @persisted_reservations
    |> :persistent_term.get(%{})
    |> Map.new(fn {token, reservation} ->
      if Process.alive?(reservation.owner) do
        monitor = Process.monitor(reservation.owner)
        {token, %{reservation | monitor: monitor, owner_alive?: true}}
      else
        {token, %{reservation | monitor: nil, owner_alive?: false}}
      end
    end)
  end

  defp persist_reservations(reservations) do
    persisted =
      Map.new(reservations, fn {token, reservation} ->
        {token, %{reservation | monitor: nil}}
      end)

    :persistent_term.put(@persisted_reservations, persisted)
  end

  # One permit covers the inventory and token write. Releases wait for that
  # decision; copying and hashing remain in the caller, outside the GenServer.
  defp release(token) do
    _result = GenServer.call(__MODULE__, {:release, token}, :infinity)
    :ok
  end

  defp admission_decision(snapshot, reservations, tekoa_id, incoming_size) do
    usage = capacity_usage(snapshot, reservations, tekoa_id, incoming_size)
    check_limits(snapshot, usage)
  end

  defp capacity_usage(snapshot, reservations, tekoa_id, incoming_size) do
    active_ids = MapSet.new(snapshot.active_uploads, & &1.public_id)

    partition_reservations =
      Enum.filter(reservations, fn {_token, reservation} ->
        reservation.tekoa_id == tekoa_id and reservation.storage_root == snapshot.storage_root
      end)

    pending_reservations =
      Enum.reject(partition_reservations, fn {_token, reservation} ->
        MapSet.member?(active_ids, reservation.public_id)
      end)

    active_bytes = Enum.reduce(snapshot.active_uploads, 0, &(&1.size + &2))

    pending_bytes =
      Enum.reduce(pending_reservations, 0, fn {_token, reservation}, total ->
        total + reservation.size
      end)

    same_tekoa_pending_bytes =
      Enum.reduce(pending_reservations, 0, fn {_token, reservation}, total ->
        if reservation.tekoa_id == tekoa_id, do: total + reservation.size, else: total
      end)

    active_staging_names =
      MapSet.new(snapshot.active_uploads, &Path.basename(&1.staging_key))

    reservation_ids =
      for {_token, reservation} <- partition_reservations,
          reservation.owner_alive? and Process.alive?(reservation.owner),
          do: reservation.public_id

    disk_pending_bytes =
      reservations
      |> Enum.filter(fn {_token, reservation} ->
        reservation.owner_alive? and Process.alive?(reservation.owner)
      end)
      |> Enum.reduce(0, fn {_token, reservation}, total -> total + reservation.size end)

    orphan_entries =
      Enum.reject(snapshot.staging_entries, fn entry ->
        MapSet.member?(active_staging_names, entry.name) or
          Enum.any?(reservation_ids, &reservation_owns_entry?(&1, entry.name))
      end)

    orphan_bytes = Enum.reduce(orphan_entries, 0, &(&1.size + &2))

    %{
      active_count: length(snapshot.active_uploads),
      active_bytes: active_bytes,
      pending_count: length(pending_reservations),
      pending_bytes: pending_bytes,
      disk_pending_bytes: disk_pending_bytes,
      same_tekoa_pending_bytes: same_tekoa_pending_bytes,
      orphan_count: length(orphan_entries),
      orphan_bytes: orphan_bytes,
      incoming_bytes: active_bytes + pending_bytes + orphan_bytes + incoming_size,
      incoming_size: incoming_size
    }
  end

  defp check_limits(snapshot, usage) do
    cond do
      is_integer(snapshot.storage_quota_bytes) and
          snapshot.storage_used_bytes + usage.active_bytes + usage.same_tekoa_pending_bytes +
            usage.orphan_bytes + usage.incoming_size >
            snapshot.storage_quota_bytes ->
        {:error, :storage_quota_exceeded}

      usage.active_count + usage.pending_count + usage.orphan_count + 1 > @max_active_upload_rows ->
        {:error, :storage_quota_exceeded}

      usage.incoming_bytes > pending_byte_budget(snapshot.max_blob_size) ->
        {:error, :storage_quota_exceeded}

      not enough_disk?(
        snapshot.disk_free_bytes,
        usage.active_bytes,
        usage.disk_pending_bytes,
        usage.orphan_bytes,
        usage.incoming_size
      ) ->
        {:error, :storage_quota_exceeded}

      true ->
        :ok
    end
  end

  defp enough_disk?(:unavailable, _active_bytes, _pending_bytes, _orphan_bytes, _incoming_size), do: true

  defp enough_disk?(free_bytes, active_bytes, pending_bytes, orphan_bytes, incoming_size) do
    required_bytes =
      active_bytes + pending_bytes * 2 + orphan_bytes + incoming_size * 2 +
        @disk_clear_headroom_bytes

    free_bytes >= required_bytes
  end

  defp reservation_owns_entry?(public_id, name) do
    name == public_id or
      (String.starts_with?(name, public_id <> "-") and String.ends_with?(name, ".part"))
  end

  defp prune_reservations(reservations) do
    # DB snapshots account for persisted rows; the owner releases each token
    # only after its enqueue operation has resolved.
    {expired, remaining} =
      Enum.split_with(reservations, fn {_token, reservation} ->
        not reservation.owner_alive? or not Process.alive?(reservation.owner)
      end)

    Enum.each(expired, fn {_token, reservation} ->
      if reservation.monitor, do: Process.demonitor(reservation.monitor, [:flush])
    end)

    Map.new(remaining)
  end
end
