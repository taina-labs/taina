defmodule Taina.Ybira.Uploads do
  @moduledoc """
  Stages web uploads and owns their durable queue state.

  User-facing operations are scoped to the current owner. Worker operations use
  the globally unique upload public ID only to discover the Tekoa, then reread
  the upload inside that Tekoa's context.
  """

  import Ecto.Query

  alias Taina.Repo
  alias Taina.Scope, as: ProductScope
  alias Taina.Ybira.Upload
  alias Taina.Ybira.UploadAdmissions
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.Scope

  require Logger

  @worker "Taina.Ybira.Workers.Ingest"
  @small_queue "uploads_small"
  @large_queue "uploads_large"
  @large_threshold 64 * 1024 * 1024
  @staging_directory "staging/uploads"
  @copy_chunk_size 64 * 1024
  @max_relative_path_bytes 8 * 1024
  @max_relative_path_segments 32
  @default_list_limit 50
  @max_list_limit 100
  @active_states [:queued, :processing]
  @event_prefix "ybira:uploads:"

  @type error ::
          :already_claimed
          | :blob_too_large
          | :database_error
          | :empty_file
          | :enqueue_failed
          | :invalid_filename
          | :invalid_relative_path
          | :invalid_scope
          | :invalid_size
          | :invalid_staging_key
          | :invalid_transition
          | :not_found
          | :owner_inactive
          | :size_mismatch
          | :staging_failed
          | :staging_invalid
          | :staging_missing
          | :storage_quota_exceeded
  @type error_code :: Upload.error_code()
  @type opts :: keyword()
  @type params :: map()
  @type path :: Path.t()
  @type scope :: Scope.t()
  @type text :: String.t()
  @type upload :: Upload.t()

  @doc """
  Moves a completed temporary upload into private staging and atomically inserts
  its upload row and Oban job.

  `attrs` must contain the browser-accepted `:filename` and `:size`. The size is
  checked against the source and staged file, and is never used for queue
  selection. `:folder_rkey` is an optional destination snapshot.
  """
  @spec stage_and_enqueue(scope(), path(), params()) :: {:ok, upload()} | {:error, error()}
  def stage_and_enqueue(%Scope{} = scope, source_path, %{} = attrs) when is_binary(source_path) do
    with {:ok, source} <- validate_source_path(source_path),
         :ok <- valid_scope(scope),
         {:ok, metadata} <- validate_input(source, attrs) do
      admit_and_enqueue(scope, source, metadata)
    end
  end

  def stage_and_enqueue(_scope, _source_path, _attrs), do: {:error, :invalid_size}

  defp admit_and_enqueue(scope, source, metadata) do
    public_id = Ecto.UUID.generate()
    staging_key = @staging_directory <> "/" <> public_id

    UploadAdmissions.with_reservation(
      scope.tekoa.id,
      public_id,
      metadata.size,
      fn -> admission_snapshot(scope) end,
      fn -> stage_and_enqueue_with_permit(scope, source, metadata, public_id, staging_key) end
    )
  end

  defp stage_and_enqueue_with_permit(scope, source, metadata, public_id, staging_key) do
    with {:ok, _target} <- stage_file(source, public_id, metadata.size) do
      enqueue_staged(scope, metadata, public_id, staging_key)
    end
  end

  @doc """
  Lists the current owner's recent uploads, newest first.

  Pass `states: [:queued, :processing]` to list only active work. The default
  limit is 50 and the maximum is 100.
  """
  @spec list(scope(), opts()) :: {:ok, [upload()]} | {:error, error()}
  def list(scope, opts \\ [])

  def list(%Scope{} = scope, opts) when is_list(opts) do
    limit = Keyword.get(opts, :limit, @default_list_limit)
    states = Keyword.get(opts, :states)

    with :ok <- valid_scope(scope),
         :ok <- valid_limit(limit),
         :ok <- valid_states(states) do
      with_tekoa(scope, fn -> {:ok, owner_uploads(scope, limit, states)} end)
    end
  end

  def list(_scope, _opts), do: {:error, :invalid_scope}

  defp owner_uploads(scope, limit, states) do
    query =
      from(upload in Upload,
        where:
          upload.tekoa_id == ^scope.tekoa.id and
            upload.dono_id == ^scope.ava.id,
        order_by: [desc: upload.inserted_at, desc: upload.id],
        limit: ^limit
      )

    query
    |> maybe_filter_states(states)
    |> preload([:dono, :tekoa, :file])
    |> Repo.all()
  end

  defp maybe_filter_states(query, nil), do: query
  defp maybe_filter_states(query, states), do: where(query, [upload], upload.state in ^states)

  @doc "Lists only queued and processing uploads belonging to the current owner."
  def list_active(%Scope{} = scope, opts \\ []) do
    list(scope, Keyword.put(opts, :states, @active_states))
  end

  @doc "Lists recent uploads belonging to the current owner."
  def list_recent(%Scope{} = scope, opts \\ []), do: list(scope, opts)

  @doc """
  Claims an upload for a job, constrained to the current owner.

  A repeated claim by the same job is idempotent. A completed upload is
  returned unchanged so a worker can avoid repeating ingestion.
  """
  @spec claim_processing(scope(), text(), pos_integer()) :: {:ok, upload()} | {:error, error()}
  def claim_processing(%Scope{} = scope, public_id, job_id)
      when is_binary(public_id) and is_integer(job_id) and job_id > 0 do
    transition_for_owner(scope, public_id, fn upload -> claim(upload, job_id) end)
  end

  def claim_processing(_scope, _public_id, _job_id), do: {:error, :invalid_transition}

  @doc """
  Marks a queued or processing upload failed with a safe, predeclared code.
  Repeating the same terminal transition for the owning job is idempotent.
  """
  @spec mark_failed(scope(), text(), pos_integer(), error_code()) :: {:ok, upload()} | {:error, error()}
  def mark_failed(%Scope{} = scope, public_id, job_id, error_code)
      when is_binary(public_id) and is_integer(job_id) and job_id > 0 do
    if safe_error_code?(error_code) do
      transition_for_owner(scope, public_id, fn upload -> fail(upload, job_id, error_code) end)
    else
      {:error, :invalid_transition}
    end
  end

  def mark_failed(_scope, _public_id, _job_id, _error_code), do: {:error, :invalid_transition}

  @doc """
  Completes an upload for the owning job.

  Call this inside the same Tekoa database transaction that commits the Ybira
  file. It only updates database state and does not notify or touch staging.
  """
  @spec mark_completed(scope(), text(), pos_integer(), pos_integer()) :: {:ok, upload()} | {:error, error()}
  def mark_completed(%Scope{} = scope, public_id, job_id, file_id)
      when is_binary(public_id) and is_integer(job_id) and job_id > 0 and is_integer(file_id) and file_id > 0 do
    transition_for_owner(scope, public_id, fn upload -> complete(upload, job_id, file_id) end, false)
  end

  def mark_completed(_scope, _public_id, _job_id, _file_id), do: {:error, :invalid_transition}

  @doc """
  Reloads an upload for a trusted job, resolving its Tekoa before the scoped read.
  """
  @spec fetch_for_job(text()) :: {:ok, upload()} | {:error, error()}
  def fetch_for_job(public_id) when is_binary(public_id) do
    with_job_upload(public_id, fn upload -> {:ok, {upload, false}} end, false)
  end

  def fetch_for_job(_public_id), do: {:error, :not_found}

  @doc "Claims an upload by its durable job ID for a trusted Oban worker."
  def claim_processing_for_job(public_id, job_id) when is_binary(public_id) and is_integer(job_id) and job_id > 0 do
    with_job_upload(public_id, fn upload -> claim(upload, job_id) end)
  end

  def claim_processing_for_job(_public_id, _job_id), do: {:error, :invalid_transition}

  @doc """
  Claims an upload for ingestion and reloads its owner and Tekoa into a safe
  scope. The system lookup that resolves the Tekoa is completed before entering
  that Tekoa's context.
  """
  @spec claim_for_ingest(text(), pos_integer()) :: {:ok, upload(), scope()} | {:error, error()}
  def claim_for_ingest(public_id, job_id) when is_binary(public_id) and is_integer(job_id) and job_id > 0 do
    with {:ok, tekoa_public_id} <- tekoa_for_upload(public_id),
         {:ok, {upload, scope, changed?}} <- claim_in_tekoa(tekoa_public_id, public_id, job_id) do
      if changed?, do: notify(upload)
      {:ok, upload, scope}
    end
  end

  def claim_for_ingest(_public_id, _job_id), do: {:error, :invalid_transition}

  @doc "Marks an upload failed by its durable job ID for a trusted Oban worker."
  def mark_failed_for_job(public_id, job_id, error_code)
      when is_binary(public_id) and is_integer(job_id) and job_id > 0 do
    if safe_error_code?(error_code) do
      with_job_upload(public_id, fn upload -> fail(upload, job_id, error_code) end)
    else
      {:error, :invalid_transition}
    end
  end

  def mark_failed_for_job(_public_id, _job_id, _error_code), do: {:error, :invalid_transition}

  @doc "Returns a transiently failed ingestion to the queued state for the same job."
  def requeue_for_job(public_id, job_id) when is_binary(public_id) and is_integer(job_id) and job_id > 0 do
    with_job_upload(public_id, fn upload -> requeue(upload, job_id) end)
  end

  def requeue_for_job(_public_id, _job_id), do: {:error, :invalid_transition}

  @doc """
  Marks an upload completed by its durable job ID.

  Call from inside the file-success transaction's current Tekoa context. This
  function emits no notification; use `notify/1` after the outer transaction
  commits.
  """
  def mark_completed_for_job(public_id, job_id, file_id)
      when is_binary(public_id) and is_integer(job_id) and job_id > 0 and is_integer(file_id) and file_id > 0 do
    case Repo.one(from(upload in Upload, where: upload.public_id == ^public_id)) do
      nil ->
        {:error, :not_found}

      upload ->
        case complete(upload, job_id, file_id) do
          {:ok, {upload, _changed?}} -> {:ok, upload}
          {:error, _reason} = error -> error
        end
    end
  end

  def mark_completed_for_job(_public_id, _job_id, _file_id), do: {:error, :invalid_transition}

  @doc """
  Runs `callback` with the validated staged-file path.

  The absolute path is only available during the callback and is not returned
  by this API. The callback is normally the Ybira ingestion pipeline.
  """
  @spec with_staged_file(upload(), (path() -> term())) :: term()
  def with_staged_file(%Upload{} = upload, callback) when is_function(callback, 1) do
    with {:ok, entry} <- safe_staging_path(upload),
         {:ok, stat} <- staged_stat(entry),
         :ok <- validate_staged_stat(upload, stat) do
      callback.(entry)
    end
  end

  @doc "Removes an upload's staged file without exposing its absolute path."
  @spec delete_staged_file(upload()) :: :ok | {:error, error()}
  def delete_staged_file(%Upload{} = upload) do
    with {:ok, entry} <- safe_staging_path(upload) do
      case File.rm(entry) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, _reason} -> {:error, :staging_failed}
      end
    end
  end

  def delete_staged_file(_upload), do: {:error, :invalid_staging_key}

  @doc "Subscribes the current owner to upload-state notifications."
  @spec subscribe(scope()) :: :ok | {:error, :invalid_scope}
  def subscribe(%Scope{} = scope) do
    with :ok <- valid_scope(scope) do
      Phoenix.PubSub.subscribe(Taina.PubSub, topic(scope.tekoa.id, scope.ava.id))
    end
  end

  @doc """
  Broadcasts an upload state after its database transaction commits.

  Subscribers receive `{:ybira_upload, public_id, state}` and should reload the
  row rather than treating PubSub as durable state.
  """
  @spec notify(upload()) :: :ok | {:error, term()}
  def notify(%Upload{} = upload) do
    Phoenix.PubSub.broadcast(
      Taina.PubSub,
      topic(upload.tekoa_id, upload.dono_id),
      {:ybira_upload, upload.public_id, upload.state}
    )
  end

  def notify(_upload), do: {:error, :invalid_upload}

  defp enqueue_staged(scope, metadata, public_id, staging_key) do
    case enqueue_transaction_result(scope, metadata, public_id, staging_key) do
      {:ok, upload} ->
        _ = notify(upload)
        {:ok, upload}

      {:error, reason} ->
        resolve_enqueue_failure(scope, public_id, staging_key, reason)
    end
  end

  defp enqueue_transaction_result(scope, metadata, public_id, staging_key) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      enqueue_transaction(scope, metadata, public_id, staging_key)
    end)
  rescue
    error in [Exqlite.Error, DBConnection.ConnectionError] ->
      log_database_exception(:enqueue, error)
      {:error, :enqueue_failed}
  end

  defp enqueue_transaction(scope, metadata, public_id, staging_key) do
    with :ok <- reserve_capacity(scope, metadata.size),
         {:ok, upload} <- insert_upload(scope, metadata, public_id, staging_key),
         queue = queue_for_size(metadata.size),
         {:ok, job} <- insert_job(public_id, queue) do
      attach_job(upload, job.id)
    end
  end

  defp insert_upload(scope, metadata, public_id, staging_key) do
    %Upload{tekoa_id: scope.tekoa.id, dono_id: scope.ava.id}
    |> Upload.changeset(%{
      public_id: public_id,
      folder_rkey: metadata.folder_rkey,
      relative_path: metadata.relative_path,
      filename: metadata.filename,
      size: metadata.size,
      staging_key: staging_key,
      state: :queued
    })
    |> Repo.insert()
    |> case do
      {:ok, upload} -> {:ok, upload}
      {:error, _changeset} -> {:error, :enqueue_failed}
    end
  end

  defp insert_job(public_id, queue) do
    job =
      Oban.Job.new(%{"upload_id" => public_id},
        worker: @worker,
        queue: queue,
        max_attempts: 3
      )

    case Repo.insert(job) do
      {:ok, job} -> {:ok, job}
      {:error, _changeset} -> {:error, :enqueue_failed}
    end
  end

  defp attach_job(upload, job_id) do
    case upload |> Upload.changeset(%{oban_job_id: job_id}) |> Repo.update() do
      {:ok, upload} -> {:ok, upload}
      {:error, _changeset} -> {:error, :enqueue_failed}
    end
  end

  defp reserve_capacity(scope, incoming_size) do
    case Repo.get(Tekoa, scope.tekoa.id) do
      nil ->
        {:error, :database_error}

      tekoa ->
        {pending_count, pending_bytes} = active_upload_totals(scope.tekoa.id)
        reserve_totals(tekoa, pending_count, pending_bytes, incoming_size)
    end
  end

  defp reserve_totals(tekoa, pending_count, pending_bytes, incoming_size) do
    reserved_bytes = tekoa.storage_used_bytes + pending_bytes + incoming_size

    pending_byte_budget =
      UploadAdmissions.pending_byte_budget(Taina.Ybira.max_blob_size())

    cond do
      is_integer(tekoa.storage_quota_bytes) and reserved_bytes > tekoa.storage_quota_bytes ->
        {:error, :storage_quota_exceeded}

      pending_count + 1 > UploadAdmissions.max_active_rows() ->
        {:error, :storage_quota_exceeded}

      pending_bytes + incoming_size > pending_byte_budget ->
        {:error, :storage_quota_exceeded}

      true ->
        :ok
    end
  end

  defp active_upload_totals(tekoa_id) do
    Repo.one(
      from(upload in Upload,
        where: upload.tekoa_id == ^tekoa_id and upload.state in ^@active_states,
        select: {count(upload.id), coalesce(sum(upload.size), 0)}
      )
    ) || {0, 0}
  end

  defp admission_snapshot(scope) do
    with {:ok, root} <- storage_root(),
         {:ok, accounting} <- with_tekoa(scope, fn -> admission_accounting(scope) end),
         {:ok, staging_entries} <- staging_inventory(root) do
      {:ok,
       Map.merge(accounting, %{
         storage_root: root,
         staging_entries: staging_entries,
         disk_free_bytes: disk_free_bytes(),
         max_blob_size: Taina.Ybira.max_blob_size()
       })}
    end
  end

  defp admission_accounting(scope) do
    case Repo.get(Tekoa, scope.tekoa.id) do
      nil ->
        {:error, :database_error}

      tekoa ->
        active_uploads =
          Repo.all(
            from(upload in Upload,
              where: upload.tekoa_id == ^scope.tekoa.id and upload.state in ^@active_states,
              select: %{
                public_id: upload.public_id,
                size: upload.size,
                staging_key: upload.staging_key
              }
            )
          )

        {:ok,
         %{
           storage_used_bytes: tekoa.storage_used_bytes,
           storage_quota_bytes: tekoa.storage_quota_bytes,
           active_uploads: active_uploads
         }}
    end
  end

  defp staging_inventory(root) do
    with {:ok, parent} <- safe_join(root, Path.dirname(@staging_directory)),
         {:ok, directory} <- safe_join(root, @staging_directory) do
      case File.lstat(parent) do
        {:error, :enoent} ->
          {:ok, []}

        {:ok, %{type: :directory}} ->
          list_staging_entries(directory)

        _other ->
          {:error, :staging_failed}
      end
    end
  end

  defp list_staging_entries(directory) do
    case File.lstat(directory) do
      {:error, :enoent} ->
        {:ok, []}

      {:ok, %{type: :directory}} ->
        with {:ok, names} <- File.ls(directory),
             :ok <- staging_directory_within_limit(names) do
          staging_entries(names, directory)
        end

      _other ->
        {:error, :staging_failed}
    end
  end

  defp staging_directory_within_limit(names) do
    if Enum.count_until(names, UploadAdmissions.max_active_rows() + 1) <=
         UploadAdmissions.max_active_rows() do
      :ok
    else
      {:error, :storage_quota_exceeded}
    end
  end

  defp staging_entries(names, directory) when is_list(names) do
    Enum.reduce_while(names, {:ok, []}, fn name, {:ok, entries} ->
      with true <- Path.basename(name) == name and name not in ["", ".", ".."],
           {:ok, entry} <- safe_join(directory, name),
           {:ok, stat} <- File.lstat(entry),
           {:ok, size} <- staging_entry_size(stat) do
        {:cont, {:ok, [%{name: name, size: size} | entries]}}
      else
        _other -> {:halt, {:error, :staging_failed}}
      end
    end)
  end

  defp staging_entry_size(%{type: :regular, size: size}) when is_integer(size) and size >= 0, do: {:ok, max(size, 1)}

  defp staging_entry_size(%{type: :symlink, size: size}) when is_integer(size) and size >= 0, do: {:ok, max(size, 1)}

  defp staging_entry_size(_stat), do: {:error, :staging_failed}

  defp disk_free_bytes do
    case Taina.Disk.stats() do
      {:ok, %{free_bytes: free_bytes}} when is_integer(free_bytes) and free_bytes >= 0 ->
        free_bytes

      {:error, :unavailable} ->
        :unavailable
    end
  end

  defp resolve_enqueue_failure(scope, public_id, staging_key, reason) do
    case lookup_owner_upload(scope, public_id) do
      {:ok, %Upload{} = upload} ->
        _ = notify(upload)
        {:ok, upload}

      {:error, :not_found} ->
        case cleanup_key(staging_key, public_id) do
          :ok -> {:error, safe_enqueue_error(reason)}
          {:error, :staging_failed} -> {:error, :staging_failed}
        end

      {:error, _reason} ->
        {:error, :database_error}
    end
  end

  defp lookup_owner_upload(scope, public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      case Repo.one(
             from(upload in Upload,
               where:
                 upload.public_id == ^public_id and
                   upload.tekoa_id == ^scope.tekoa.id and
                   upload.dono_id == ^scope.ava.id
             )
           ) do
        nil -> {:error, :not_found}
        upload -> {:ok, upload}
      end
    end)
  rescue
    error in [Exqlite.Error, DBConnection.ConnectionError] ->
      log_database_exception(:reconcile_enqueue, error)
      {:error, :database_error}
  end

  defp log_database_exception(operation, error) do
    Logger.error("Ybira upload database operation failed: #{operation} (#{inspect(error.__struct__)})")
  end

  defp safe_enqueue_error(:storage_quota_exceeded), do: :storage_quota_exceeded
  defp safe_enqueue_error(:database_error), do: :database_error
  defp safe_enqueue_error(_reason), do: :enqueue_failed

  defp transition_for_owner(scope, public_id, transition, notify? \\ true) do
    with :ok <- valid_scope(scope),
         {:ok, {upload, changed?}} <-
           with_tekoa(scope, fn -> owner_transition(scope, public_id, transition) end) do
      if changed? and notify?, do: notify(upload)
      {:ok, upload}
    end
  end

  defp owner_transition(scope, public_id, transition) do
    query =
      from(upload in Upload,
        where:
          upload.public_id == ^public_id and
            upload.tekoa_id == ^scope.tekoa.id and
            upload.dono_id == ^scope.ava.id
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      upload -> transition.(upload)
    end
  end

  defp with_job_upload(public_id, callback, notify? \\ true) do
    with {:ok, tekoa_public_id} <- tekoa_for_upload(public_id),
         {:ok, {upload, changed?}} <-
           safe_with_tekoa(tekoa_public_id, fn -> job_upload_transition(public_id, callback) end) do
      if changed? and notify?, do: notify(upload)
      {:ok, upload}
    end
  end

  defp job_upload_transition(public_id, callback) do
    case Repo.one(from(upload in Upload, where: upload.public_id == ^public_id)) do
      nil -> {:error, :not_found}
      upload -> callback.(upload)
    end
  end

  defp tekoa_for_upload(public_id) do
    Repo.with_system(fn ->
      case Repo.one(
             from(upload in Upload,
               join: tekoa in Tekoa,
               on: tekoa.id == upload.tekoa_id,
               where: upload.public_id == ^public_id,
               select: tekoa.public_id
             ),
             skip_tekoa_id: true
           ) do
        nil -> {:error, :not_found}
        tekoa_public_id -> {:ok, tekoa_public_id}
      end
    end)
  end

  defp worker_identity(%Upload{} = upload) do
    with %Tekoa{} = tekoa <- Repo.get(Tekoa, upload.tekoa_id),
         %Ava{} = ava <- Repo.get(Ava, upload.dono_id),
         true <- ava.tekoa_id == tekoa.id do
      {:ok, ava, tekoa}
    else
      nil -> {:error, :owner_inactive}
      false -> {:error, :owner_inactive}
    end
  end

  defp claim_in_tekoa(tekoa_public_id, public_id, job_id) do
    safe_with_tekoa(tekoa_public_id, fn ->
      case Repo.one(from(upload in Upload, where: upload.public_id == ^public_id)) do
        nil -> {:error, :not_found}
        upload -> claim_upload(upload, job_id)
      end
    end)
  end

  defp claim_upload(%Upload{} = upload, job_id) do
    with {:ok, ava, tekoa} <- worker_identity(upload),
         {:ok, {claimed, changed?}} <- claim(upload, job_id) do
      {:ok, {claimed, ProductScope.new(ava, tekoa), changed?}}
    end
  end

  defp claim(%Upload{state: :completed, oban_job_id: job_id} = upload, job_id), do: {:ok, {upload, false}}
  defp claim(%Upload{state: :completed}, _job_id), do: {:error, :invalid_transition}

  defp claim(%Upload{state: :queued, oban_job_id: job_id} = upload, job_id) do
    update_transition(upload, %{state: :processing})
  end

  defp claim(%Upload{state: :processing, oban_job_id: job_id} = upload, job_id), do: {:ok, {upload, false}}

  defp claim(%Upload{state: :processing}, _job_id), do: {:error, :already_claimed}
  defp claim(%Upload{state: :failed}, _job_id), do: {:error, :invalid_transition}
  defp claim(%Upload{}, _job_id), do: {:error, :invalid_transition}

  defp fail(%Upload{state: :failed, oban_job_id: job_id, error_code: error_code} = upload, job_id, error_code),
    do: {:ok, {upload, false}}

  defp fail(%Upload{state: state, oban_job_id: job_id} = upload, job_id, error_code)
       when state in [:queued, :processing] do
    update_transition(upload, %{state: :failed, error_code: error_code})
  end

  defp fail(%Upload{state: state}, _job_id, _error_code) when state in [:queued, :processing],
    do: {:error, :already_claimed}

  defp fail(%Upload{}, _job_id, _error_code), do: {:error, :invalid_transition}

  defp requeue(%Upload{state: :queued, oban_job_id: job_id} = upload, job_id), do: {:ok, {upload, false}}

  defp requeue(%Upload{state: :processing, oban_job_id: job_id} = upload, job_id) do
    update_transition(upload, %{state: :queued, error_code: nil})
  end

  defp requeue(%Upload{state: state}, _job_id) when state in [:queued, :processing], do: {:error, :already_claimed}

  defp requeue(%Upload{}, _job_id), do: {:error, :invalid_transition}

  defp complete(%Upload{state: :completed, oban_job_id: job_id, file_id: file_id} = upload, job_id, file_id),
    do: {:ok, {upload, false}}

  defp complete(%Upload{state: :processing, oban_job_id: job_id} = upload, job_id, file_id) do
    update_transition(upload, %{state: :completed, file_id: file_id, error_code: nil})
  end

  defp complete(%Upload{state: :completed}, _job_id, _file_id), do: {:error, :invalid_transition}
  defp complete(%Upload{}, _job_id, _file_id), do: {:error, :invalid_transition}

  defp update_transition(upload, attrs) do
    case upload |> Upload.changeset(attrs) |> Repo.update() do
      {:ok, upload} -> {:ok, {upload, true}}
      {:error, _changeset} -> {:error, :database_error}
    end
  end

  defp with_tekoa(%Scope{} = scope, callback) do
    safe_with_tekoa(scope.tekoa.public_id, callback)
  end

  defp safe_with_tekoa(tekoa_public_id, callback) do
    Repo.with_tekoa(tekoa_public_id, callback)
  end

  defp validate_input(source_path, attrs) do
    filename = Map.get(attrs, :filename)
    expected_size = Map.get(attrs, :size)
    folder_rkey = Map.get(attrs, :folder_rkey)
    relative_path = Map.get(attrs, :relative_path)

    with :ok <- validate_filename(filename),
         :ok <- validate_expected_size(expected_size),
         :ok <- validate_folder_rkey(folder_rkey),
         :ok <- validate_relative_path(relative_path, filename),
         {:ok, stat} <- source_stat(source_path),
         :ok <- validate_size(stat.size, expected_size) do
      {:ok,
       %{
         filename: filename,
         size: stat.size,
         folder_rkey: folder_rkey,
         relative_path: relative_path
       }}
    end
  end

  defp validate_source_path(source_path) when is_binary(source_path) do
    temporary_root = Path.expand(System.tmp_dir!())
    candidate = Path.expand(source_path)

    if Path.type(source_path) == :absolute and path_beneath?(temporary_root, candidate) do
      {:ok, candidate}
    else
      {:error, :staging_invalid}
    end
  end

  defp path_beneath?(root, candidate) do
    relative = Path.relative_to(candidate, root)

    relative not in [".", ""] and Path.type(relative) == :relative and
      Enum.all?(Path.split(relative), &(&1 not in ["", ".."]))
  end

  defp validate_filename(filename) when is_binary(filename) and byte_size(filename) > 0 and byte_size(filename) <= 255 do
    if String.valid?(filename) and filename not in [".", ".."] and
         not String.contains?(filename, ["/", "\\", <<0>>]) do
      :ok
    else
      {:error, :invalid_filename}
    end
  end

  defp validate_filename(_filename), do: {:error, :invalid_filename}

  defp validate_expected_size(size) when is_integer(size) and size > 0, do: :ok
  defp validate_expected_size(_size), do: {:error, :invalid_size}

  defp validate_folder_rkey(nil), do: :ok

  defp validate_folder_rkey(rkey) when is_binary(rkey) and byte_size(rkey) > 0 and byte_size(rkey) <= 255 do
    if String.valid?(rkey) and not String.contains?(rkey, <<0>>) do
      :ok
    else
      {:error, :invalid_size}
    end
  end

  defp validate_folder_rkey(_rkey), do: {:error, :invalid_size}

  defp validate_relative_path(relative_path, _filename) when relative_path in [nil, ""], do: :ok

  defp validate_relative_path(relative_path, filename)
       when is_binary(relative_path) and byte_size(relative_path) <= @max_relative_path_bytes do
    segments = String.split(relative_path, "/")

    if String.valid?(relative_path) and length(segments) <= @max_relative_path_segments and
         List.last(segments) == filename and Enum.all?(segments, &valid_relative_segment?/1) do
      :ok
    else
      {:error, :invalid_relative_path}
    end
  end

  defp validate_relative_path(_relative_path, _filename), do: {:error, :invalid_relative_path}

  defp valid_relative_segment?(segment) do
    segment not in ["", ".", ".."] and String.valid?(segment) and String.length(segment) <= 255 and
      not String.contains?(segment, ["\\", <<0>>])
  end

  defp source_stat(source) do
    case File.lstat(source) do
      {:ok, %{type: :regular, size: size}} when size > 0 ->
        if size <= Taina.Ybira.max_blob_size(),
          do: {:ok, %{size: size}},
          else: {:error, :blob_too_large}

      {:ok, %{type: :regular}} ->
        {:error, :empty_file}

      {:ok, _other} ->
        {:error, :staging_invalid}

      {:error, _reason} ->
        {:error, :staging_missing}
    end
  end

  defp validate_size(actual, expected) when actual == expected, do: :ok
  defp validate_size(_actual, _expected), do: {:error, :size_mismatch}

  defp stage_file(source, public_id, expected_size) do
    with {:ok, directory} <- ensure_staging_directory(),
         {:ok, target} <- target_path(directory, public_id),
         {:ok, partial} <- part_path(directory, public_id),
         :ok <- move_or_copy(source, target, partial) do
      with {:ok, stat} <- staged_stat(target),
           :ok <- validate_staged_size(stat, expected_size) do
        {:ok, target}
      else
        _error ->
          _ = remove_if_present(target)
          _ = remove_if_present(partial)
          {:error, :staging_failed}
      end
    end
  end

  defp part_path(directory, public_id) do
    safe_join(directory, public_id <> "-" <> Ecto.UUID.generate() <> ".part")
  end

  defp ensure_staging_directory do
    with {:ok, root} <- storage_root(),
         {:ok, directory} <- safe_join(root, @staging_directory),
         {:ok, parent} <- safe_join(root, Path.dirname(@staging_directory)),
         :ok <- safe_mkdir_p(directory),
         :ok <- real_directory?(parent),
         :ok <- real_directory?(directory) do
      {:ok, directory}
    else
      {:error, _reason} -> {:error, :staging_failed}
    end
  end

  defp storage_root do
    case Application.get_env(:taina, :storage_root) do
      <<_::utf8, _::binary>> = root -> {:ok, Path.expand(root)}
      _other -> {:error, :staging_failed}
    end
  end

  defp safe_join(root, relative) do
    candidate = Path.expand(relative, root)

    if path_beneath?(Path.expand(root), candidate) do
      {:ok, candidate}
    else
      {:error, :invalid_staging_key}
    end
  end

  defp safe_mkdir_p(directory) do
    case File.mkdir_p(directory) do
      :ok -> :ok
      {:error, _reason} -> {:error, :staging_failed}
    end
  end

  defp real_directory?(directory) do
    case File.lstat(directory) do
      {:ok, %{type: :directory}} -> :ok
      _other -> {:error, :staging_failed}
    end
  end

  defp target_path(directory, public_id) do
    with {:ok, canonical_id} <- Ecto.UUID.cast(public_id),
         true <- canonical_id == public_id do
      safe_join(directory, canonical_id)
    else
      _other -> {:error, :staging_failed}
    end
  end

  defp move_or_copy(source, target, partial) do
    case File.rename(source, target) do
      :ok ->
        :ok

      {:error, :exdev} ->
        copy_across_devices(source, partial, target)

      {:error, _reason} ->
        {:error, :staging_failed}
    end
  end

  defp copy_across_devices(source, partial, target) do
    with {:ok, copied_size} <- stream_to_part(source, partial),
         {:ok, stat} <- staged_stat(partial),
         :ok <- validate_staged_size(stat, copied_size),
         :ok <- rename_part(partial, target),
         :ok <- remove_source(source) do
      :ok
    else
      _error ->
        _ = remove_if_present(partial)
        _ = remove_if_present(target)
        {:error, :staging_failed}
    end
  end

  defp remove_source(source) do
    case File.rm(source) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} -> {:error, :staging_failed}
    end
  end

  defp stream_to_part(source, partial) do
    case File.open(source, [:read, :binary, :raw]) do
      {:ok, input} ->
        try do
          case File.open(partial, [:write, :binary, :raw, :exclusive]) do
            {:ok, output} ->
              try do
                copy_and_sync(input, output)
              after
                _ = File.close(output)
              end

            {:error, _reason} ->
              {:error, :staging_failed}
          end
        after
          _ = File.close(input)
        end

      {:error, _reason} ->
        {:error, :staging_failed}
    end
  end

  defp copy_and_sync(source, target) do
    with {:ok, bytes} <- copy_chunks(source, target, 0),
         :ok <- :file.sync(target) do
      {:ok, bytes}
    else
      _error -> {:error, :staging_failed}
    end
  end

  defp copy_chunks(source, target, copied_bytes) do
    case :file.read(source, @copy_chunk_size) do
      {:ok, chunk} ->
        case :file.write(target, chunk) do
          :ok -> copy_chunks(source, target, copied_bytes + byte_size(chunk))
          {:error, _reason} -> {:error, :staging_failed}
        end

      :eof ->
        {:ok, copied_bytes}

      {:error, _reason} ->
        {:error, :staging_failed}
    end
  end

  defp rename_part(partial, target) do
    case File.rename(partial, target) do
      :ok -> :ok
      {:error, _reason} -> {:error, :staging_failed}
    end
  end

  defp validate_staged_size(%{type: :regular, size: size}, expected_size) when size > 0 and size == expected_size, do: :ok

  defp validate_staged_size(_stat, _expected_size), do: {:error, :staging_invalid}

  defp safe_staging_path(%Upload{public_id: public_id, staging_key: staging_key}) do
    expected_key = @staging_directory <> "/" <> to_string(public_id)

    with true <- is_binary(public_id) and staging_key == expected_key,
         {:ok, canonical_id} <- Ecto.UUID.cast(public_id),
         true <- canonical_id == public_id,
         {:ok, root} <- storage_root(),
         {:ok, entry} <- safe_join(root, expected_key),
         {:ok, parent} <- safe_join(root, Path.dirname(@staging_directory)),
         {:ok, directory} <- safe_join(root, @staging_directory),
         :ok <- real_directory?(parent),
         :ok <- real_directory?(directory) do
      {:ok, entry}
    else
      {:error, :staging_failed} -> {:error, :staging_failed}
      _other -> {:error, :invalid_staging_key}
    end
  end

  defp staged_stat(entry) do
    case File.lstat(entry) do
      {:ok, stat} -> {:ok, stat}
      {:error, :enoent} -> {:error, :staging_missing}
      {:error, _reason} -> {:error, :staging_failed}
    end
  end

  defp cleanup_key(staging_key, public_id) do
    upload = %Upload{public_id: public_id, staging_key: staging_key}

    case safe_staging_path(upload) do
      {:ok, entry} -> remove_if_present(entry)
      {:error, :staging_failed} = error -> error
      {:error, _reason} -> :ok
    end
  end

  defp remove_if_present(entry) do
    case File.rm(entry) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, _reason} -> {:error, :staging_failed}
    end
  end

  defp validate_staged_stat(%Upload{size: size}, %{type: :regular, size: size}), do: :ok
  defp validate_staged_stat(_upload, %{type: :regular}), do: {:error, :staging_invalid}
  defp validate_staged_stat(_upload, _stat), do: {:error, :staging_invalid}

  defp valid_scope(%Scope{tekoa: %{id: tekoa_id, public_id: public_id}, ava: %{tekoa_id: tekoa_id}})
       when is_integer(tekoa_id) and is_binary(public_id), do: :ok

  defp valid_scope(_scope), do: {:error, :invalid_scope}

  defp valid_limit(limit) when is_integer(limit) and limit in 1..@max_list_limit, do: :ok
  defp valid_limit(_limit), do: {:error, :invalid_size}

  defp valid_states(nil), do: :ok

  defp valid_states(states) when is_list(states) do
    if states != [] and Enum.all?(states, &(&1 in [:queued, :processing, :completed, :failed])),
      do: :ok,
      else: {:error, :invalid_transition}
  end

  defp valid_states(_states), do: {:error, :invalid_transition}

  defp safe_error_code?(error_code) do
    error_code in [
      :blob_too_large,
      :folder_unavailable,
      :invalid_mime,
      :owner_inactive,
      :processing_failed,
      :staging_invalid,
      :staging_missing,
      :storage_quota_exceeded,
      :upload_conflict
    ]
  end

  defp queue_for_size(size) when size >= @large_threshold, do: @large_queue
  defp queue_for_size(_size), do: @small_queue

  defp topic(tekoa_id, dono_id), do: @event_prefix <> "#{tekoa_id}:#{dono_id}"
end
