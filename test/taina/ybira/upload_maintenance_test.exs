defmodule Taina.Ybira.UploadMaintenanceTest do
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

    old_orphan = Path.join(uploads_directory(ctx), Ecto.UUID.generate())
    old_part = Path.join(uploads_directory(ctx), part_filename())
    recent_orphan = Path.join(uploads_directory(ctx), Ecto.UUID.generate())
    recent_part = Path.join(uploads_directory(ctx), part_filename())

    for path <- [old_orphan, old_part, recent_orphan, recent_part] do
      File.write!(path, "staging bytes")
    end

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

  test "removes staging for terminal rows without pruning their history", ctx do
    upload = stage(ctx, "terminal.txt")
    staged_path = staged_path(ctx, upload)

    assert {:ok, failed} =
             Uploads.mark_failed_for_job(upload.public_id, upload.oban_job_id, :processing_failed)

    assert failed.state == :failed
    assert File.exists?(staged_path)

    assert {:ok, result} = UploadMaintenance.run()
    assert result.terminal_staging_cleaned == 1
    refute File.exists?(staged_path)

    assert {:ok, retained} = Uploads.fetch_for_job(upload.public_id)
    assert retained.state == :failed
    assert retained.id == upload.id
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

  defp staged_path(ctx, upload) do
    Path.join([ctx.storage_root, "staging", "uploads", upload.public_id])
  end

  defp uploads_directory(ctx), do: Path.join([ctx.storage_root, "staging", "uploads"])

  defp part_filename do
    Ecto.UUID.generate() <> "-" <> Ecto.UUID.generate() <> ".part"
  end
end
