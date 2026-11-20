defmodule Taina.Ybira.UploadMaintenanceTest do
  # Each test changes the application-wide storage_root used by staging.
  use Taina.DataCase, async: false

  import Taina.Fixtures

  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira.Upload
  alias Taina.Ybira.UploadMaintenance
  alias Taina.Ybira.Uploads

  @old_time {{2020, 1, 1}, {0, 0, 0}}

  setup do
    root = Path.join(System.tmp_dir!(), "taina_upload_maintenance_#{Ecto.UUID.generate()}")
    storage_root = Path.join(root, "storage")
    previous_storage_root = Application.get_env(:taina, :storage_root)
    Application.put_env(:taina, :storage_root, storage_root)

    on_exit(fn ->
      Application.put_env(:taina, :storage_root, previous_storage_root)
      File.rm_rf!(root)
    end)

    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa)

    %{root: root, storage_root: storage_root, scope: Scope.new(owner, tekoa)}
  end

  test "fails nonterminal rows when staged input is missing and notifies after commit", ctx do
    upload = stage(ctx, "missing.txt")
    assert :ok = Uploads.delete_staged_file(upload)
    :ok = Uploads.subscribe(ctx.scope)

    assert {:ok, result} = UploadMaintenance.run()
    assert result.failed == 1

    assert {:ok, failed} = Uploads.fetch_for_job(upload.public_id)
    assert failed.state == :failed
    assert failed.error_code == :staging_missing
    assert_receive {:ybira_upload, public_id, :failed}
    assert public_id == upload.public_id
  end

  test "fails rows whose job was discarded or pruned", ctx do
    discarded_upload = stage(ctx, "discarded.txt")
    missing_job_upload = stage(ctx, "missing-job.txt")

    assert {:ok, %{state: :processing}} =
             Uploads.claim_processing_for_job(discarded_upload.public_id, discarded_upload.oban_job_id)

    assert {:ok, %{state: :processing}} =
             Uploads.claim_processing_for_job(missing_job_upload.public_id, missing_job_upload.oban_job_id)

    Repo.update_all(
      from(job in Oban.Job, where: job.id == ^discarded_upload.oban_job_id),
      set: [state: "discarded"]
    )

    missing_job = Repo.get!(Oban.Job, missing_job_upload.oban_job_id)
    Repo.delete!(missing_job)

    assert {:ok, result} = UploadMaintenance.run()
    assert result.failed == 2

    for upload <- [discarded_upload, missing_job_upload] do
      assert {:ok, failed} = Uploads.fetch_for_job(upload.public_id)
      assert failed.state == :failed
      assert failed.error_code == :processing_failed
    end
  end

  test "cleans old unowned files but keeps recent files and old referenced staging", ctx do
    active_upload = stage(ctx, "active.txt")
    active_path = staged_path(ctx, active_upload)
    :ok = File.touch(active_path, @old_time)

    old_orphan = write_staging_fixture(ctx, Ecto.UUID.generate())
    old_part = write_staging_fixture(ctx, part_filename())
    recent_orphan = write_staging_fixture(ctx, Ecto.UUID.generate())
    recent_part = write_staging_fixture(ctx, part_filename())

    :ok = File.touch(old_orphan, @old_time)
    :ok = File.touch(old_part, @old_time)

    assert {:ok, result} = UploadMaintenance.run()
    assert result.orphan_files_cleaned == 2

    assert File.exists?(active_path)
    refute File.exists?(old_orphan)
    refute File.exists?(old_part)
    assert File.exists?(recent_orphan)
    assert File.exists?(recent_part)
  end

  test "cleans aged terminal staging and prunes history only after 30 days", ctx do
    grace_upload = failed_upload(ctx, "grace-terminal.txt")
    grace_staged_path = staged_path(ctx, grace_upload)
    age_terminal_row(ctx, grace_upload, 2)
    :ok = File.touch(grace_staged_path, @old_time)

    expired_upload = failed_upload(ctx, "expired-terminal.txt")
    expired_staged_path = staged_path(ctx, expired_upload)
    age_terminal_row(ctx, expired_upload, 31)
    :ok = File.touch(expired_staged_path, @old_time)

    expired_with_recent_file = failed_upload(ctx, "expired-recent-file.txt")
    age_terminal_row(ctx, expired_with_recent_file, 31)
    recent_staged_path = staged_path(ctx, expired_with_recent_file)

    recent_upload = failed_upload(ctx, "recent-terminal.txt")
    recent_upload_staged_path = staged_path(ctx, recent_upload)

    assert {:ok, result} = UploadMaintenance.run()
    assert result.terminal_staging_cleaned == 2
    assert result.terminal_history_pruned == 1

    refute File.exists?(grace_staged_path)
    refute File.exists?(expired_staged_path)
    assert File.exists?(recent_staged_path)
    assert File.exists?(recent_upload_staged_path)

    assert {:ok, %{state: :failed, id: grace_id}} = Uploads.fetch_for_job(grace_upload.public_id)
    assert grace_id == grace_upload.id
    assert {:error, :not_found} = Uploads.fetch_for_job(expired_upload.public_id)
    assert {:ok, %{state: :failed}} = Uploads.fetch_for_job(expired_with_recent_file.public_id)
    assert {:ok, %{state: :failed}} = Uploads.fetch_for_job(recent_upload.public_id)
  end

  defp stage(ctx, filename) do
    source = Path.join(ctx.root, filename)
    File.write!(source, "staged contents")

    assert {:ok, %Upload{} = upload} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{
               filename: filename,
               size: byte_size("staged contents")
             })

    upload
  end

  defp failed_upload(ctx, filename) do
    upload = stage(ctx, filename)

    assert {:ok, %{state: :failed}} =
             Uploads.mark_failed_for_job(upload.public_id, upload.oban_job_id, :processing_failed)

    upload
  end

  defp age_terminal_row(ctx, upload, days) do
    updated_at =
      DateTime.utc_now()
      |> DateTime.shift(day: -days)
      |> DateTime.truncate(:second)

    assert {:ok, 1} =
             Repo.with_tekoa(ctx.scope.tekoa.public_id, fn ->
               {updated, _rows} =
                 Repo.update_all(
                   from(row in Upload, where: row.id == ^upload.id),
                   set: [updated_at: updated_at]
                 )

               {:ok, updated}
             end)
  end

  defp staged_path(ctx, upload) do
    Path.join([ctx.storage_root, "staging", "uploads", upload.public_id])
  end

  defp uploads_directory(ctx), do: Path.join([ctx.storage_root, "staging", "uploads"])

  defp write_staging_fixture(ctx, name) do
    assert generated_staging_filename?(name)
    base = Path.expand(uploads_directory(ctx))
    candidate = Path.expand(name, base)
    assert Path.dirname(candidate) == base
    assert Path.basename(candidate) == name
    File.write!(candidate, "staging bytes")
    candidate
  end

  defp generated_staging_filename?(name) do
    match?({:ok, ^name}, Ecto.UUID.cast(name)) or
      Regex.match?(
        ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.part\z/,
        name
      )
  end

  defp part_filename do
    Ecto.UUID.generate() <> "-" <> Ecto.UUID.generate() <> ".part"
  end
end
