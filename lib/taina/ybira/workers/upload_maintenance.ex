defmodule Taina.Ybira.Workers.UploadMaintenance do
  @moduledoc """
  Runs upload recovery and staging cleanup as a system maintenance job.
  """

  use Oban.Worker, queue: :default

  alias Taina.Ybira.UploadMaintenance

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case UploadMaintenance.run() do
      {:ok, result} ->
        Logger.info("UploadMaintenance completed",
          failed: result.failed,
          terminal_staging_cleaned: result.terminal_staging_cleaned,
          orphan_files_cleaned: result.orphan_files_cleaned,
          cleanup_errors: result.cleanup_errors
        )

        :ok

      {:error, _reason} = error ->
        error
    end
  end
end
