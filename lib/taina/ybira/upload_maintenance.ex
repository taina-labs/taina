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
  @part_filename_regex ~r/\A([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.part\z/

  @type result :: %{
          failed: non_neg_integer(),
          terminal_staging_cleaned: non_neg_integer(),
          orphan_files_cleaned: non_neg_integer(),
          cleanup_errors: non_neg_integer()
        }

  @doc """
  Reconciles missing or abandoned upload work, then cleans safe staging files.

  Missing input fails with `:staging_missing`. An active row whose job is
  discarded or no longer exists fails with `:processing_failed`. Terminal
  upload rows are retained as domain history.
  """
  @spec run() :: {:ok, result()} | {:error, :database_error}
  def run do
    case Repo.with_system(&reconcile/0) do
      {:ok, reconciliation} -> {:ok, finish(reconciliation)}
      {:error, _reason} -> {:error, :database_error}
    end
  rescue
    _error -> {:error, :database_error}
  end

  defp reconcile do
    uploads = Repo.all(from(upload in Upload, order_by: upload.id), skip_tekoa_id: true)
    job_states = job_states(uploads)

    terminal_uploads = Enum.filter(uploads, &(&1.state in @terminal_states))

    with {:ok, active_uploads, newly_failed} <- reconcile_active(uploads, job_states) do
      {:ok,
       %{
         active_uploads: active_uploads,
         known_public_ids: MapSet.new(Enum.map(uploads, & &1.public_id)),
         terminal_uploads: terminal_uploads ++ newly_failed,
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
        from(job in Oban.Job,
          where: job.id in ^job_ids,
          select: {job.id, job.state}
        )
        |> Repo.all(skip_tekoa_id: true)
        |> Map.new()
    end
  end

  defp reconcile_active(uploads, job_states) do
    uploads
    |> Enum.filter(&(&1.state in @active_states))
    |> Enum.reduce_while({:ok, [], []}, fn upload, {:ok, active, failed} ->
      case failure_code(upload, job_states) do
        nil ->
          {:cont, {:ok, [upload | active], failed}}

        error_code ->
          case fail(upload, error_code) do
            {:ok, failed_upload} ->
              {:cont, {:ok, active, [failed_upload | failed]}}

            {:error, _reason} ->
              {:halt, {:error, :database_error}}
          end
      end
    end)
    |> case do
      {:ok, active, failed} -> {:ok, Enum.reverse(active), Enum.reverse(failed)}
      {:error, _reason} = error -> error
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

  defp finish(reconciliation) do
    {terminal_cleaned, terminal_errors} = clean_terminal_staging(reconciliation.terminal_uploads)

    {orphan_cleaned, orphan_errors} =
      clean_old_unowned_files(
        reconciliation.active_uploads,
        reconciliation.known_public_ids,
        System.os_time(:second)
      )

    Enum.each(reconciliation.notify_uploads, &Uploads.notify/1)

    %{
      failed: reconciliation.failed,
      terminal_staging_cleaned: terminal_cleaned,
      orphan_files_cleaned: orphan_cleaned,
      cleanup_errors: terminal_errors + orphan_errors
    }
  end

  defp clean_terminal_staging(uploads) do
    Enum.reduce(uploads, {0, 0}, fn upload, {cleaned, errors} ->
      case Uploads.delete_staged_file(upload) do
        :ok -> {cleaned + 1, errors}
        {:error, _reason} -> {cleaned, errors + 1}
      end
    end)
  end

  defp clean_old_unowned_files(active_uploads, known_public_ids, now) do
    active_public_ids = MapSet.new(active_uploads, & &1.public_id)

    case staging_directory() do
      {:ok, directory} ->
        case File.ls(directory) do
          {:ok, names} ->
            Enum.reduce(names, {0, 0}, fn name, {cleaned, errors} ->
              cleanup_orphan(directory, name, active_public_ids, known_public_ids, now, cleaned, errors)
            end)

          {:error, _reason} ->
            {0, 0}
        end

      :error ->
        {0, 0}
    end
  end

  defp cleanup_orphan(directory, name, active_ids, known_ids, now, cleaned, errors) do
    cond do
      valid_upload_id?(name) and (MapSet.member?(active_ids, name) or MapSet.member?(known_ids, name)) ->
        {cleaned, errors}

      not generated_staging_filename?(name) ->
        {cleaned, errors}

      true ->
        delete_if_old(Path.join(directory, name), now, cleaned, errors)
    end
  end

  defp delete_if_old(path, now, cleaned, errors) do
    case File.lstat(path, time: :posix) do
      {:ok, %{type: :regular, mtime: mtime}} when is_integer(mtime) and now - mtime >= @staging_grace_seconds ->
        case File.rm(path) do
          :ok -> {cleaned + 1, errors}
          {:error, :enoent} -> {cleaned, errors}
          {:error, _reason} -> {cleaned, errors + 1}
        end

      _other ->
        {cleaned, errors}
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
      root when is_binary(root) and root != "" ->
        staging = Path.join(root, "staging")
        directory = Path.join(staging, "uploads")

        with {:ok, %{type: :directory}} <- File.lstat(staging),
             {:ok, %{type: :directory}} <- File.lstat(directory) do
          {:ok, directory}
        else
          _other -> :error
        end

      _other ->
        :error
    end
  end
end
