defmodule Taina.Ybira.UploadMaintenance do
  @moduledoc """
  Reconciles durable upload state and removes staging files no longer owned by
  active uploads.

  This is a system operation that crosses Tekoas. Database reads and state
  transitions run inside `Repo.with_system/1` with explicit `skip_tekoa_id`
  options. Notifications and filesystem cleanup happen after that transaction
  commits.
  """

  import Ecto.Query

  alias Taina.Repo
  alias Taina.Ybira.Upload
  alias Taina.Ybira.Uploads

  @active_states [:queued, :processing]
  @terminal_states [:completed, :failed]
  @staging_grace_seconds 24 * 60 * 60
  @history_retention_seconds 30 * 24 * 60 * 60
  @part_filename_regex ~r/\A([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.part\z/

  @type result :: %{
          failed: non_neg_integer(),
          terminal_staging_cleaned: non_neg_integer(),
          orphan_files_cleaned: non_neg_integer(),
          terminal_history_pruned: non_neg_integer(),
          cleanup_errors: non_neg_integer()
        }

  @doc """
  Reconciles active work, then cleans eligible staging files and old terminal
  history.

  Missing input fails with `:staging_missing`. An active row whose job is
  discarded or no longer exists fails with `:processing_failed`. Terminal
  staging is cleaned after 24 hours. Terminal rows are retained for 30 days.
  """
  @spec run() :: {:ok, result()} | {:error, :database_error}
  def run do
    now = DateTime.truncate(DateTime.utc_now(), :second)
    grace_cutoff = DateTime.shift(now, second: -@staging_grace_seconds)
    retention_cutoff = DateTime.shift(now, second: -@history_retention_seconds)

    with {:ok, reconciliation} <- Repo.with_system(&reconcile_active/0),
         {:ok, result} <-
           finish(reconciliation, grace_cutoff, retention_cutoff, DateTime.to_unix(now)) do
      {:ok, result}
    else
      {:error, _reason} -> {:error, :database_error}
    end
  rescue
    _error -> {:error, :database_error}
  end

  defp reconcile_active do
    uploads =
      Repo.all(
        from(upload in Upload,
          where: upload.state in ^@active_states,
          order_by: upload.id
        ),
        skip_tekoa_id: true
      )

    job_states = job_states(uploads)

    with {:ok, active_uploads, newly_failed} <- reconcile_active(uploads, job_states) do
      {:ok,
       %{
         active_public_ids: MapSet.new(Enum.map(active_uploads, & &1.public_id)),
         notify_uploads: newly_failed,
         failed: length(newly_failed)
       }}
    end
  end

  defp job_states(uploads) do
    job_ids =
      uploads
      |> Enum.map(& &1.oban_job_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    case job_ids do
      [] ->
        %{}

      _job_ids ->
        job_rows =
          Repo.all(
            from(job in Oban.Job,
              where: job.id in ^job_ids,
              select: {job.id, job.state}
            ),
            skip_tekoa_id: true
          )

        Map.new(job_rows)
    end
  end

  defp reconcile_active(uploads, job_states) do
    uploads
    |> Enum.filter(&(&1.state in @active_states))
    |> Enum.reduce_while({:ok, [], []}, fn upload, state ->
      reconcile_upload(upload, job_states, state)
    end)
    |> case do
      {:ok, active, failed} -> {:ok, Enum.reverse(active), Enum.reverse(failed)}
      {:error, _reason} = error -> error
    end
  end

  defp reconcile_upload(upload, job_states, {:ok, active, failed}) do
    case failure_code(upload, job_states) do
      nil ->
        {:cont, {:ok, [upload | active], failed}}

      error_code ->
        fail_active_upload(upload, error_code, active, failed)
    end
  end

  defp fail_active_upload(upload, error_code, active, failed) do
    case fail(upload, error_code) do
      {:ok, failed_upload} -> {:cont, {:ok, active, [failed_upload | failed]}}
      {:error, _reason} -> {:halt, {:error, :database_error}}
    end
  end

  defp failure_code(upload, job_states) do
    cond do
      staging_missing?(upload) ->
        :staging_missing

      is_nil(Map.get(job_states, upload.oban_job_id)) ->
        :processing_failed

      Map.get(job_states, upload.oban_job_id) == "discarded" ->
        :processing_failed

      true ->
        nil
    end
  end

  defp staging_missing?(upload) do
    case Uploads.with_staged_file(upload, fn _path -> :present end) do
      {:error, :staging_missing} -> true
      _other -> false
    end
  end

  defp fail(upload, error_code) do
    upload
    |> Upload.changeset(%{state: :failed, error_code: error_code})
    |> Repo.update(skip_tekoa_id: true)
  end

  defp finish(reconciliation, grace_cutoff, retention_cutoff, now) do
    Enum.each(reconciliation.notify_uploads, &Uploads.notify/1)

    with {:ok, {terminal_cleaned, orphan_cleaned, staging_errors}} <-
           clean_old_staging(reconciliation.active_public_ids, grace_cutoff, now),
         {:ok, {history_pruned, history_staging_cleaned, history_errors}} <-
           prune_terminal_history(retention_cutoff, grace_cutoff, now) do
      {:ok,
       %{
         failed: reconciliation.failed,
         terminal_staging_cleaned: terminal_cleaned + history_staging_cleaned,
         orphan_files_cleaned: orphan_cleaned,
         terminal_history_pruned: history_pruned,
         cleanup_errors: staging_errors + history_errors
       }}
    end
  end

  defp clean_old_staging(active_public_ids, grace_cutoff, now) do
    with {:ok, directory} <- staging_directory(),
         {:ok, entries} <- old_staging_entries(directory, active_public_ids, now),
         {:ok, uploads} <- uploads_for_staging_entries(entries) do
      {:ok, clean_staging_entries(entries, uploads, active_public_ids, grace_cutoff)}
    else
      :error -> {:ok, {0, 0, 0}}
      {:error, _reason} = error -> error
    end
  end

  defp old_staging_entries(directory, active_public_ids, now) do
    case File.ls(directory) do
      {:ok, names} ->
        entries =
          Enum.flat_map(names, fn name ->
            old_staging_entry(directory, name, active_public_ids, now)
          end)

        {:ok, entries}

      {:error, _reason} ->
        {:ok, []}
    end
  end

  defp old_staging_entry(directory, name, active_public_ids, now) do
    if valid_upload_id?(name) and MapSet.member?(active_public_ids, name) do
      []
    else
      old_staging_entry_for_name(directory, name, now)
    end
  end

  defp old_staging_entry_for_name(directory, name, now) do
    with {:ok, candidate} <- staging_entry(directory, name),
         {:ok, %{type: :regular, mtime: mtime}} when now - mtime >= @staging_grace_seconds <-
           File.lstat(candidate, time: :posix) do
      [{name, candidate}]
    else
      _other -> []
    end
  end

  defp uploads_for_staging_entries(entries) do
    public_ids = for {name, _candidate} <- entries, valid_upload_id?(name), do: name

    case public_ids do
      [] ->
        {:ok, %{}}

      _public_ids ->
        Repo.with_system(fn ->
          uploads =
            Repo.all(
              from(upload in Upload, where: upload.public_id in ^public_ids),
              skip_tekoa_id: true
            )

          {:ok, Map.new(uploads, &{&1.public_id, &1})}
        end)
    end
  end

  defp clean_staging_entries(entries, uploads, active_public_ids, grace_cutoff) do
    Enum.reduce(entries, {0, 0, 0}, fn {name, candidate}, counts ->
      clean_staging_entry(name, candidate, uploads, active_public_ids, grace_cutoff, counts)
    end)
  end

  defp clean_staging_entry(name, candidate, uploads, active_public_ids, grace_cutoff, counts) do
    cond do
      valid_upload_id?(name) and MapSet.member?(active_public_ids, name) ->
        counts

      valid_upload_id?(name) ->
        clean_upload_staging(name, candidate, uploads, grace_cutoff, counts)

      true ->
        clean_orphan_staging(candidate, counts)
    end
  end

  defp clean_upload_staging(public_id, candidate, uploads, grace_cutoff, counts) do
    case Map.get(uploads, public_id) do
      nil ->
        clean_orphan_staging(candidate, counts)

      %Upload{state: state} when state in @active_states ->
        counts

      %Upload{state: state, updated_at: updated_at} = upload
      when state in @terminal_states ->
        clean_terminal_staging(upload, updated_at, grace_cutoff, counts)
    end
  end

  defp clean_terminal_staging(upload, updated_at, grace_cutoff, counts) do
    if DateTime.compare(updated_at, grace_cutoff) in [:lt, :eq] do
      delete_terminal_staging(upload, counts)
    else
      counts
    end
  end

  defp delete_terminal_staging(upload, counts) do
    case Uploads.delete_staged_file(upload) do
      :ok -> increment_terminal_cleaned(counts)
      {:error, _reason} -> increment_cleanup_errors(counts)
    end
  end

  defp clean_orphan_staging(candidate, {terminal_cleaned, orphan_cleaned, errors}) do
    case File.rm(candidate) do
      :ok -> {terminal_cleaned, orphan_cleaned + 1, errors}
      {:error, :enoent} -> {terminal_cleaned, orphan_cleaned, errors}
      {:error, _reason} -> {terminal_cleaned, orphan_cleaned, errors + 1}
    end
  end

  defp prune_terminal_history(retention_cutoff, grace_cutoff, now) do
    Repo.with_system(fn ->
      expired_uploads =
        Repo.all(
          from(upload in Upload,
            where:
              upload.state in ^@terminal_states and
                upload.updated_at <= ^retention_cutoff,
            order_by: [asc: upload.updated_at, asc: upload.id]
          ),
          skip_tekoa_id: true
        )

      expired_uploads
      |> Enum.reduce_while({:ok, 0, 0, 0}, fn upload, counts ->
        prune_expired_upload(upload, grace_cutoff, now, counts)
      end)
      |> case do
        {:ok, pruned, staging_cleaned, errors} -> {:ok, {pruned, staging_cleaned, errors}}
        {:error, _reason} = error -> error
      end
    end)
  end

  defp prune_expired_upload(upload, grace_cutoff, now, {:ok, pruned, staging_cleaned, errors}) do
    case terminal_staging_state(upload, grace_cutoff, now) do
      {:ok, :recent} ->
        {:cont, {:ok, pruned, staging_cleaned, errors}}

      {:ok, staging_state} ->
        delete_expired_upload(upload, staging_state, pruned, staging_cleaned, errors)

      {:error, _reason} ->
        {:cont, {:ok, pruned, staging_cleaned, errors + 1}}
    end
  end

  defp delete_expired_upload(upload, staging_state, pruned, staging_cleaned, errors) do
    case Repo.delete(upload, skip_tekoa_id: true) do
      {:ok, _deleted} ->
        cleaned =
          case staging_state do
            :cleaned -> staging_cleaned + 1
            _other -> staging_cleaned
          end

        {:cont, {:ok, pruned + 1, cleaned, errors}}

      {:error, _changeset} ->
        {:halt, {:error, :database_error}}
    end
  end

  defp terminal_staging_state(upload, grace_cutoff, now) do
    with {:ok, candidate} <- upload_staging_entry(upload) do
      candidate
      |> File.lstat(time: :posix)
      |> terminal_staging_result(upload, grace_cutoff, now)
    end
  end

  defp terminal_staging_result({:error, :enoent}, _upload, _grace_cutoff, _now), do: {:ok, :absent}

  defp terminal_staging_result({:ok, %{type: :regular, mtime: mtime}}, upload, grace_cutoff, now)
       when is_integer(mtime) and now - mtime >= @staging_grace_seconds do
    if DateTime.compare(upload.updated_at, grace_cutoff) in [:lt, :eq] do
      remove_expired_staging(upload)
    else
      {:ok, :recent}
    end
  end

  defp terminal_staging_result({:ok, _recent_or_invalid}, _upload, _grace_cutoff, _now), do: {:ok, :recent}

  defp terminal_staging_result({:error, _reason}, _upload, _grace_cutoff, _now), do: {:error, :staging_failed}

  defp remove_expired_staging(upload) do
    case Uploads.delete_staged_file(upload) do
      :ok -> {:ok, :cleaned}
      {:error, _reason} -> {:error, :staging_failed}
    end
  end

  defp upload_staging_entry(%Upload{public_id: public_id, staging_key: staging_key}) do
    expected_key = "staging/uploads/" <> to_string(public_id)

    with true <- staging_key == expected_key,
         true <- valid_upload_id?(public_id),
         <<_::utf8, _::binary>> = root <- Application.get_env(:taina, :storage_root),
         directory = Path.join([Path.expand(root), "staging", "uploads"]),
         {:ok, candidate} <- staging_entry(directory, public_id) do
      {:ok, candidate}
    else
      _other -> {:error, :invalid_staging_key}
    end
  end

  defp increment_terminal_cleaned({terminal_cleaned, orphan_cleaned, errors}),
    do: {terminal_cleaned + 1, orphan_cleaned, errors}

  defp increment_cleanup_errors({terminal_cleaned, orphan_cleaned, errors}),
    do: {terminal_cleaned, orphan_cleaned, errors + 1}

  defp staging_entry(directory, name) do
    with true <- generated_staging_filename?(name),
         expanded_directory = Path.expand(directory),
         candidate = Path.expand(name, expanded_directory),
         true <- Path.dirname(candidate) == expanded_directory,
         true <- Path.basename(candidate) == name do
      {:ok, candidate}
    else
      _other -> :error
    end
  end

  defp generated_staging_filename?(name) do
    valid_upload_id?(name) or valid_part_filename?(name)
  end

  defp valid_upload_id?(name) do
    case Ecto.UUID.cast(name) do
      {:ok, ^name} -> true
      _other -> false
    end
  end

  defp valid_part_filename?(name) do
    case Regex.run(@part_filename_regex, name, capture: :all_but_first) do
      [upload_id, part_id] -> valid_upload_id?(upload_id) and valid_upload_id?(part_id)
      _other -> false
    end
  end

  defp staging_directory do
    case Application.get_env(:taina, :storage_root) do
      <<_::utf8, _::binary>> = root ->
        staging = root |> Path.expand() |> Path.join("staging")
        directory = Path.join(staging, "uploads")

        with {:ok, %{type: :directory}} <- File.lstat(staging),
             {:ok, %{type: :directory}} <- File.lstat(directory) do
          {:ok, Path.expand(directory)}
        else
          _other -> :error
        end

      _other ->
        :error
    end
  end
end
