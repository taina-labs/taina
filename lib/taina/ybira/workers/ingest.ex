defmodule Taina.Ybira.Workers.Ingest do
  @moduledoc """
  Ingests one staged upload into Ybira.

  Jobs carry only the upload public ID. Uploads resolves the Tekoa, claims the
  row for this job, and reloads a scope before any file work begins.
  """

  use Oban.Worker, max_attempts: 3

  alias Taina.Maraca
  alias Taina.Repo
  alias Taina.Ybira
  alias Taina.Ybira.Upload
  alias Taina.Ybira.Uploads
  alias Taina.Ybira.Workers.Rendition
  alias Ypy.Ybira.File, as: YbiraFile

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"upload_id" => upload_id}} = job) when is_binary(upload_id) do
    case Uploads.claim_for_ingest(upload_id, job.id) do
      {:ok, %Upload{state: :completed} = upload, _scope} ->
        finish_completed(upload, job)

      {:ok, %Upload{} = upload, scope} ->
        perform_claimed(job, upload, scope)

      {:error, :owner_inactive} ->
        fail_deterministically(job, upload_id, :owner_inactive)

      {:error, :database_error} = error ->
        transient_failure(job, upload_id, error)

      {:error, :not_found} ->
        {:cancel, :upload_not_found}

      {:error, reason} ->
        Logger.warning("Ingest claim rejected for upload #{upload_id} on attempt #{job.attempt}",
          reason: inspect(reason)
        )

        {:cancel, :upload_unavailable}
    end
  end

  def perform(%Oban.Job{}), do: {:cancel, :invalid_job}

  defp perform_claimed(job, %Upload{} = upload, scope) do
    if Maraca.activated?(scope.ava) do
      ingest_staged_file(job, upload, scope)
    else
      fail_deterministically(job, upload, :owner_inactive)
    end
  rescue
    error ->
      Logger.warning(
        "Ingest raised while processing upload #{upload.public_id} on attempt #{job.attempt}",
        reason: inspect(error)
      )

      recover_after_error(job, upload, :processing_failed)
  end

  defp ingest_staged_file(job, upload, scope) do
    result =
      Uploads.with_staged_file(upload, fn staged_path ->
        Ybira.upload_with_success(
          scope,
          staged_path,
          [
            filename: upload.filename,
            folder_rkey: upload.folder_rkey,
            relative_path: upload.relative_path
          ],
          completion_callback(upload, job.id, scope)
        )
      end)

    case result do
      {:ok, _file} -> finish_ingested_file(job, upload)
      {:error, reason} -> handle_ingest_error(job, upload, reason)
      other -> handle_ingest_error(job, upload, {:unexpected_result, other})
    end
  end

  defp finish_ingested_file(job, upload) do
    case Uploads.fetch_for_job(upload.public_id) do
      {:ok, %Upload{state: :completed, oban_job_id: job_id} = completed} when job_id == job.id ->
        cleanup_and_notify(completed)
        :ok

      {:ok, _upload} ->
        transient_failure(job, upload, :completion_not_visible)

      {:error, reason} ->
        transient_failure(job, upload, reason)
    end
  end

  defp completion_callback(%Upload{} = upload, job_id, scope) do
    fn %YbiraFile{} = file ->
      with {:ok, _completed} <- Uploads.mark_completed_for_job(upload.public_id, job_id, file.id) do
        enqueue_rendition(file, scope)
      end
    end
  end

  defp enqueue_rendition(%YbiraFile{mime: "image/" <> _rest} = file, scope) do
    result =
      %{file_id: file.id, tekoa_public_id: scope.tekoa.public_id}
      |> Rendition.new()
      |> Repo.insert()

    case result do
      {:ok, _job} -> :ok
      {:error, _reason} -> {:error, :rendition_enqueue_failed}
    end
  end

  defp enqueue_rendition(%YbiraFile{}, _scope), do: :ok

  defp handle_ingest_error(job, upload, reason) do
    case error_code(reason) do
      nil -> recover_after_error(job, upload, reason)
      code -> fail_deterministically(job, upload, code)
    end
  end

  defp error_code(:staging_missing), do: :staging_missing
  defp error_code(:enoent), do: :staging_missing
  defp error_code(:staging_invalid), do: :staging_invalid
  defp error_code(:invalid_staging_key), do: :staging_invalid
  defp error_code(:blob_changed), do: :staging_invalid
  defp error_code(:blob_too_large), do: :blob_too_large
  defp error_code(:mime_not_allowed), do: :invalid_mime
  defp error_code(:storage_quota_exceeded), do: :storage_quota_exceeded
  defp error_code(:inactive_owner), do: :owner_inactive
  defp error_code(:owner_inactive), do: :owner_inactive
  defp error_code(:not_owner), do: :folder_unavailable
  defp error_code(:not_found), do: :folder_unavailable
  defp error_code(:invalid_relative_path), do: :folder_unavailable
  defp error_code(_reason), do: nil

  defp fail_deterministically(job, upload_or_id, code) do
    upload_id = upload_id(upload_or_id)

    case Uploads.mark_failed_for_job(upload_id, job.id, code) do
      {:ok, %Upload{} = failed} ->
        delete_staging(failed)
        {:cancel, code}

      {:error, _reason} ->
        case completed_for_job(upload_id, job.id) do
          {:ok, %Upload{} = completed} ->
            finish_completed(completed, job)

          _other ->
            recover_after_error(job, upload_or_id, :failure_transition_failed)
        end
    end
  end

  defp recover_after_error(job, upload_or_id, reason) do
    upload_id = upload_id(upload_or_id)

    case completed_for_job(upload_id, job.id) do
      {:ok, %Upload{} = completed} ->
        finish_completed(completed, job)

      _not_completed ->
        transient_failure(job, upload_or_id, reason)
    end
  end

  defp transient_failure(job, upload_or_id, reason) do
    upload_id = upload_id(upload_or_id)

    Logger.warning("Ingest failed for upload #{upload_id} on attempt #{job.attempt}",
      reason: inspect(reason)
    )

    if final_attempt?(job) do
      mark_transient_failure(job, upload_id)
    else
      requeue_transient_failure(job, upload_id)
    end
  end

  defp mark_transient_failure(job, upload_id) do
    case Uploads.mark_failed_for_job(upload_id, job.id, :processing_failed) do
      {:ok, %Upload{} = failed} ->
        delete_staging(failed)
        {:error, :processing_failed}

      {:error, _reason} ->
        finish_completed_or_retry(job, upload_id)
    end
  end

  defp requeue_transient_failure(job, upload_id) do
    case Uploads.requeue_for_job(upload_id, job.id) do
      {:ok, _queued} -> {:error, :processing_failed}
      {:error, _reason} -> finish_completed_or_retry(job, upload_id)
    end
  end

  defp finish_completed_or_retry(job, upload_id) do
    case completed_for_job(upload_id, job.id) do
      {:ok, %Upload{} = completed} -> finish_completed(completed, job)
      _other -> {:error, :processing_failed}
    end
  end

  defp completed_for_job(upload_id, job_id) do
    case Uploads.fetch_for_job(upload_id) do
      {:ok, %Upload{state: :completed, oban_job_id: ^job_id} = upload} -> {:ok, upload}
      {:ok, _upload} -> {:error, :not_completed}
      other -> other
    end
  end

  defp finish_completed(%Upload{} = upload, job) do
    if upload.oban_job_id == job.id do
      cleanup_and_notify(upload)
      :ok
    else
      {:cancel, :upload_unavailable}
    end
  end

  defp cleanup_and_notify(%Upload{} = upload) do
    delete_staging(upload)

    case Uploads.notify(upload) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Ingest completion notification failed for upload #{upload.public_id}",
          reason: inspect(reason)
        )
    end

    :ok
  end

  defp delete_staging(%Upload{} = upload) do
    case Uploads.delete_staged_file(upload) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Ingest staging cleanup failed for upload #{upload.public_id}",
          reason: inspect(reason)
        )
    end
  end

  defp final_attempt?(%Oban.Job{attempt: attempt, max_attempts: max_attempts})
       when is_integer(attempt) and is_integer(max_attempts), do: attempt >= max_attempts

  defp final_attempt?(_job), do: false

  defp upload_id(%Upload{public_id: public_id}), do: public_id
  defp upload_id(public_id) when is_binary(public_id), do: public_id
end
