defmodule Taina.Ybira.UploadsTest do
  # These tests change application-wide storage and upload-limit settings.
  use Taina.DataCase, async: false

  import Ecto.Query
  import Taina.Fixtures

  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira
  alias Taina.Ybira.Upload
  alias Taina.Ybira.UploadAdmissions
  alias Taina.Ybira.Uploads

  @large_threshold 64 * 1024 * 1024

  setup do
    root = Path.join(System.tmp_dir!(), "taina_uploads_test_#{Ecto.UUID.generate()}")
    previous_storage_root = Application.get_env(:taina, :storage_root)
    Application.put_env(:taina, :storage_root, Path.join(root, "storage"))

    on_exit(fn ->
      Application.put_env(:taina, :storage_root, previous_storage_root)
      File.rm_rf!(root)
    end)

    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa)

    %{
      root: root,
      tekoa: tekoa,
      owner: owner,
      scope: Scope.new(owner, tekoa),
      source_root: Path.join(root, "source")
    }
  end

  test "stages privately and inserts one scoped row and one job", ctx do
    contents = "durable upload bytes"
    source = source_file(ctx, "source.txt", contents)
    :ok = Uploads.subscribe(ctx.scope)

    assert {:ok, %Upload{} = upload} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{
               filename: "community-notes.txt",
               size: byte_size(contents),
               folder_rkey: "folder-rkey"
             })

    assert upload.state == :queued
    assert upload.tekoa_id == ctx.tekoa.id
    assert upload.dono_id == ctx.owner.id
    assert upload.filename == "community-notes.txt"
    assert upload.folder_rkey == "folder-rkey"
    assert upload.size == byte_size(contents)
    assert upload.staging_key == "staging/uploads/#{upload.public_id}"
    refute Path.type(upload.staging_key) == :absolute
    assert {:ok, ^contents} = Uploads.with_staged_file(upload, &File.read/1)
    assert_receive {:ybira_upload, public_id, :queued}
    assert public_id == upload.public_id

    job = Repo.get!(Oban.Job, upload.oban_job_id)
    assert job.worker == "Taina.Ybira.Workers.Ingest"
    assert job.queue == "uploads_small"
    assert job.args == %{"upload_id" => upload.public_id}

    assert {:ok, [listed]} = Uploads.list(ctx.scope)
    assert listed.id == upload.id
    assert {:ok, [active]} = Uploads.list_active(ctx.scope)
    assert active.id == upload.id
  end

  test "routes from the actual staged size", ctx do
    path = sparse_file(ctx, "large.bin", @large_threshold + 1)

    assert {:ok, upload} =
             Uploads.stage_and_enqueue(ctx.scope, path, %{
               filename: "large.bin",
               size: @large_threshold + 1
             })

    job = Repo.get!(Oban.Job, upload.oban_job_id)
    assert job.queue == "uploads_large"
    assert job.args == %{"upload_id" => upload.public_id}
  end

  test "reserves existing and pending bytes against the community quota", ctx do
    {:ok, tekoa} =
      ctx.tekoa
      |> Ecto.Changeset.change(storage_quota_bytes: 5, storage_used_bytes: 0)
      |> Repo.update()

    owner = %{ctx.owner | tekoa_id: tekoa.id}
    scope = Scope.new(owner, tekoa)

    first_path = source_file(ctx, "first.bin", "123")

    assert {:ok, _first} =
             Uploads.stage_and_enqueue(scope, first_path, %{filename: "first.bin", size: 3})

    second_source = source_file(ctx, "second.bin", "456")

    assert {:error, :storage_quota_exceeded} =
             Uploads.stage_and_enqueue(scope, second_source, %{filename: "second.bin", size: 3})

    assert File.read!(second_source) == "456"
    assert {:ok, [only]} = Uploads.list(scope)
    assert only.filename == "first.bin"
    assert ingest_job_count() == 1
  end

  test "concurrent admissions enforce the row limit before staging", ctx do
    {:ok, tekoa} =
      ctx.tekoa
      |> Ecto.Changeset.change(storage_quota_bytes: nil, storage_used_bytes: 0)
      |> Repo.update()

    owner = %{ctx.owner | tekoa_id: tekoa.id}
    scope = Scope.new(owner, tekoa)

    sources =
      for index <- 1..21 do
        source = source_file(ctx, "concurrent-#{index}.bin", "x")
        {source, %{filename: "concurrent-#{index}.bin", size: 1}}
      end

    results =
      sources
      |> Task.async_stream(
        fn {source, attrs} -> {source, Uploads.stage_and_enqueue(scope, source, attrs)} end,
        max_concurrency: length(sources),
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    accepted = Enum.count(results, fn {_source, result} -> match?({:ok, _upload}, result) end)
    rejected = Enum.filter(results, fn {_source, result} -> result == {:error, :storage_quota_exceeded} end)

    assert accepted == 20
    assert [{rejected_source, {:error, :storage_quota_exceeded}}] = rejected
    assert File.exists?(rejected_source)
    assert {:ok, uploads} = Uploads.list_active(scope, limit: 100)
    assert Enum.count_until(uploads, 21) == 20
  end

  test "unowned partial staging consumes the byte budget immediately with no quota", ctx do
    set_max_blob_size(4)

    {:ok, tekoa} =
      ctx.tekoa
      |> Ecto.Changeset.change(storage_quota_bytes: nil, storage_used_bytes: 0)
      |> Repo.update()

    owner = %{ctx.owner | tekoa_id: tekoa.id}
    scope = Scope.new(owner, tekoa)
    staging_directory = Path.join([Application.fetch_env!(:taina, :storage_root), "staging", "uploads"])
    File.mkdir_p!(staging_directory)

    orphan =
      Path.join(
        staging_directory,
        Ecto.UUID.generate() <> "-" <> Ecto.UUID.generate() <> ".part"
      )

    File.write!(orphan, "123456")
    source = source_file(ctx, "incoming.bin", "abc")

    assert {:error, :storage_quota_exceeded} =
             Uploads.stage_and_enqueue(scope, source, %{filename: "incoming.bin", size: 3})

    assert File.exists?(orphan)
    assert File.read!(source) == "abc"
    assert {:ok, []} = Uploads.list_active(scope)
    assert ingest_job_count() == 0
  end

  test "disk admission includes other in-flight copies", ctx do
    snapshot = %{
      storage_used_bytes: 0,
      storage_quota_bytes: nil,
      active_uploads: [],
      staging_entries: [],
      storage_root: "admission-test",
      disk_free_bytes: 64 * 1024 * 1024 + 3,
      max_blob_size: 4
    }

    parent = self()

    first =
      Task.async(fn ->
        UploadAdmissions.with_reservation(
          ctx.tekoa.id,
          Ecto.UUID.generate(),
          1,
          fn -> {:ok, snapshot} end,
          fn ->
            send(parent, {:admission_held, self()})

            receive do
              :release_admission -> :released
            end
          end
        )
      end)

    assert_receive {:admission_held, first_owner}

    assert {:error, :storage_quota_exceeded} =
             UploadAdmissions.with_reservation(
               ctx.tekoa.id,
               Ecto.UUID.generate(),
               1,
               fn -> {:ok, snapshot} end,
               fn -> :unexpected_admission end
             )

    send(first_owner, :release_admission)
    assert :released = Task.await(first)
  end

  test "serializes capacity snapshots but lets an admitted copy overlap", ctx do
    parent = self()

    snapshot = %{
      storage_used_bytes: 0,
      storage_quota_bytes: 5,
      active_uploads: [],
      staging_entries: [],
      storage_root: "admission-test",
      disk_free_bytes: :unavailable,
      max_blob_size: 4
    }

    first =
      Task.async(fn ->
        UploadAdmissions.with_reservation(
          ctx.tekoa.id,
          Ecto.UUID.generate(),
          4,
          fn ->
            send(parent, :first_snapshot_started)

            receive do
              :continue_first_snapshot -> {:ok, snapshot}
            end
          end,
          fn ->
            send(parent, :first_copy_started)

            receive do
              :finish_first_copy -> :first_copy_finished
            end
          end
        )
      end)

    assert_receive :first_snapshot_started

    second =
      Task.async(fn ->
        UploadAdmissions.with_reservation(
          ctx.tekoa.id,
          Ecto.UUID.generate(),
          2,
          fn ->
            send(parent, :second_snapshot_started)
            {:ok, snapshot}
          end,
          fn ->
            send(parent, :second_copy_started)
            :unexpected_copy
          end
        )
      end)

    send(first.pid, :continue_first_snapshot)
    assert_receive :first_copy_started
    assert_receive :second_snapshot_started
    assert {:error, :storage_quota_exceeded} = Task.await(second)
    refute_received :second_copy_started

    send(first.pid, :finish_first_copy)
    assert :first_copy_finished = Task.await(first)
  end

  test "active rows and their still-held admission token count once", ctx do
    parent = self()
    public_id = Ecto.UUID.generate()
    staging_key = "staging/uploads/#{public_id}"

    base_snapshot = %{
      storage_used_bytes: 0,
      storage_quota_bytes: nil,
      active_uploads: [],
      staging_entries: [],
      storage_root: "admission-test",
      disk_free_bytes: :unavailable,
      max_blob_size: 4
    }

    first =
      Task.async(fn ->
        UploadAdmissions.with_reservation(
          ctx.tekoa.id,
          public_id,
          4,
          fn -> {:ok, base_snapshot} end,
          fn ->
            send(parent, :first_reservation_held)

            receive do
              :release_first_reservation -> :released
            end
          end
        )
      end)

    assert_receive :first_reservation_held

    active_snapshot = %{
      base_snapshot
      | active_uploads: [
          %{public_id: public_id, size: 4, staging_key: staging_key}
        ]
    }

    assert :second_admitted =
             UploadAdmissions.with_reservation(
               ctx.tekoa.id,
               Ecto.UUID.generate(),
               4,
               fn -> {:ok, active_snapshot} end,
               fn -> :second_admitted end
             )

    send(first.pid, :release_first_reservation)
    assert :released = Task.await(first)
  end

  test "admission token is released when the staged operation raises", ctx do
    snapshot = %{
      storage_used_bytes: 0,
      storage_quota_bytes: nil,
      active_uploads: [],
      staging_entries: [],
      storage_root: "admission-test",
      disk_free_bytes: :unavailable,
      max_blob_size: 4
    }

    assert_raise RuntimeError, "forced operation failure", fn ->
      UploadAdmissions.with_reservation(
        ctx.tekoa.id,
        Ecto.UUID.generate(),
        3,
        fn -> {:ok, snapshot} end,
        fn -> raise "forced operation failure" end
      )
    end

    assert :completed =
             UploadAdmissions.with_reservation(
               ctx.tekoa.id,
               Ecto.UUID.generate(),
               3,
               fn -> {:ok, snapshot} end,
               fn -> :completed end
             )
  end

  test "rejects empty, size-mismatched, oversized and traversal inputs", ctx do
    empty = source_file(ctx, "empty.bin", "")
    mismatch = source_file(ctx, "mismatch.bin", "abc")
    traversal = source_file(ctx, "safe-source.bin", "bytes")

    assert {:error, :empty_file} =
             Uploads.stage_and_enqueue(ctx.scope, empty, %{filename: "empty.bin", size: 1})

    assert {:error, :size_mismatch} =
             Uploads.stage_and_enqueue(ctx.scope, mismatch, %{filename: "mismatch.bin", size: 2})

    previous = Application.get_env(:taina, :upload, [])
    Application.put_env(:taina, :upload, Keyword.put(previous, :max_blob_size, 4))

    on_exit(fn -> Application.put_env(:taina, :upload, previous) end)

    assert {:error, :blob_too_large} =
             Uploads.stage_and_enqueue(ctx.scope, traversal, %{filename: "large.bin", size: 5})

    assert {:error, :invalid_filename} =
             Uploads.stage_and_enqueue(ctx.scope, traversal, %{filename: "../../escape", size: 5})

    assert File.read!(traversal) == "bytes"
    assert {:ok, []} = Uploads.list(ctx.scope)
    assert ingest_job_count() == 0
  end

  test "rolls back the upload row and job together and removes staged data", ctx do
    Repo.query!("""
    CREATE TEMP TRIGGER reject_upload_job BEFORE INSERT ON oban_jobs
    BEGIN
      SELECT RAISE(ABORT, 'forced test failure');
    END
    """)

    source = source_file(ctx, "rollback.txt", "transactional")

    assert {:error, :enqueue_failed} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{
               filename: "rollback.txt",
               size: byte_size("transactional")
             })

    assert {:ok, []} = Uploads.list(ctx.scope)
    assert ingest_job_count() == 0
    assert File.ls!(Path.join([Application.fetch_env!(:taina, :storage_root), "staging", "uploads"])) == []
  end

  test "claims once and applies safe terminal transitions", ctx do
    source = source_file(ctx, "state.txt", "state")

    assert {:ok, upload} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{filename: "state.txt", size: 5})

    assert {:ok, processing} =
             Uploads.claim_processing(ctx.scope, upload.public_id, upload.oban_job_id)

    assert processing.state == :processing

    assert {:ok, repeated} =
             Uploads.claim_processing(ctx.scope, upload.public_id, upload.oban_job_id)

    assert repeated.state == :processing

    assert {:error, :already_claimed} =
             Uploads.claim_processing(ctx.scope, upload.public_id, upload.oban_job_id + 1)

    assert {:ok, failed} =
             Uploads.mark_failed_for_job(
               upload.public_id,
               upload.oban_job_id,
               :processing_failed
             )

    assert failed.state == :failed
    assert failed.error_code == :processing_failed

    assert {:ok, repeated_failure} =
             Uploads.mark_failed(ctx.scope, upload.public_id, upload.oban_job_id, :processing_failed)

    assert repeated_failure.state == :failed

    assert {:error, :invalid_transition} =
             Uploads.mark_failed(ctx.scope, upload.public_id, upload.oban_job_id, "raw exception")

    assert {:ok, []} = Uploads.list_active(ctx.scope)
  end

  test "job lookup is tenant-scoped and completion is idempotent", ctx do
    source = source_file(ctx, "complete.txt", "done")

    assert {:ok, upload} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{filename: "complete.txt", size: 4})

    assert {:ok, fetched} = Uploads.fetch_for_job(upload.public_id)
    assert fetched.id == upload.id

    assert {:ok, processing} =
             Uploads.claim_processing_for_job(upload.public_id, upload.oban_job_id)

    assert processing.state == :processing
    refute_received {:ybira_upload, _, :completed}

    file_source = source_file(ctx, "already-committed.txt", "committed file")
    assert {:ok, file} = Ybira.upload(ctx.scope, file_source, filename: "already-committed.txt")

    assert {:ok, completed} =
             Repo.with_tekoa(ctx.tekoa.public_id, fn ->
               Uploads.mark_completed_for_job(upload.public_id, upload.oban_job_id, file.id)
             end)

    assert completed.state == :completed
    assert completed.file_id == file.id

    assert {:ok, repeated} =
             Repo.with_tekoa(ctx.tekoa.public_id, fn ->
               Uploads.mark_completed_for_job(upload.public_id, upload.oban_job_id, file.id)
             end)

    assert repeated.id == completed.id
  end

  test "returns a safe staging error when the storage root is not a directory", ctx do
    blocker = Path.join(ctx.root, "storage-blocker")
    File.write!(blocker, "not a directory")
    Application.put_env(:taina, :storage_root, blocker)

    source = source_file(ctx, "blocked.txt", "contents")

    assert {:error, :staging_failed} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{
               filename: "blocked.txt",
               size: byte_size("contents")
             })

    assert File.read!(source) == "contents"
    assert {:ok, []} = Uploads.list(ctx.scope)
  end

  test "refuses an upload struct with a traversal staging key", _ctx do
    upload = %Upload{
      public_id: Ecto.UUID.generate(),
      staging_key: "staging/uploads/../../outside",
      size: 1
    }

    assert {:error, :invalid_staging_key} = Uploads.with_staged_file(upload, fn _path -> :ok end)
    assert {:error, :invalid_staging_key} = Uploads.delete_staged_file(upload)
  end

  defp source_file(ctx, name, contents) do
    File.mkdir_p!(ctx.source_root)
    filename = safe_fixture_filename(name)
    root = Path.expand(ctx.source_root)
    target = Path.expand(filename, root)
    assert Path.dirname(target) == root
    File.write!(target, contents)
    target
  end

  defp set_max_blob_size(size) do
    previous = Application.get_env(:taina, :upload, [])
    Application.put_env(:taina, :upload, Keyword.put(previous, :max_blob_size, size))
    on_exit(fn -> Application.put_env(:taina, :upload, previous) end)
  end

  defp safe_fixture_filename(name) do
    if is_binary(name) and String.valid?(name) and Path.basename(name) == name and
         name not in ["", ".", ".."] and not String.contains?(name, ["\\", <<0>>]) do
      name
    else
      raise ArgumentError, "invalid fixture filename"
    end
  end

  defp sparse_file(ctx, name, size) do
    File.mkdir_p!(ctx.source_root)
    path = Path.join(ctx.source_root, name)
    {:ok, file} = :file.open(String.to_charlist(path), [:write, :binary, :raw])
    {:ok, _position} = :file.position(file, size - 1)
    :ok = :file.write(file, "x")
    :ok = :file.close(file)
    path
  end

  defp ingest_job_count do
    Repo.aggregate(
      from(job in Oban.Job, where: job.worker == "Taina.Ybira.Workers.Ingest"),
      :count,
      :id
    )
  end
end
