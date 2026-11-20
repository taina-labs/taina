defmodule Taina.Ybira.Workers.IngestTest do
  # These tests change the process-wide storage root and observe PubSub transitions.
  use Taina.DataCase, async: false

  import Ecto.Query
  import Taina.Fixtures

  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira
  alias Taina.Ybira.BlobLock
  alias Taina.Ybira.Upload
  alias Taina.Ybira.Uploads
  alias Taina.Ybira.Workers.Ingest
  alias Taina.Ybira.Workers.Rendition
  alias Ypy.Cid
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.Mural.Store, as: MuralStore
  alias Ypy.Ybira.File, as: YbiraFile

  setup do
    root = Path.join(System.tmp_dir!(), "taina_ingest_test_#{Ecto.UUID.generate()}")
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

  test "ingests once, completes the upload and enqueues exactly one rendition", ctx do
    Oban.Testing.with_testing_mode(:manual, fn ->
      :ok = Uploads.subscribe(ctx.scope)
      source = image_file(ctx, "first.jpg")
      upload = stage(ctx, source, "first.jpg")
      assert upload_job(upload).max_attempts == 3

      assert_receive {:ybira_upload, public_id, :queued}
      assert public_id == upload.public_id

      assert :ok = Ingest.perform(job(upload, 1))
      assert_receive {:ybira_upload, ^public_id, :processing}
      assert_receive {:ybira_upload, ^public_id, :completed}

      assert {:ok, %Upload{state: :completed, file_id: file_id} = completed} =
               Uploads.fetch_for_job(upload.public_id)

      assert Repo.get!(YbiraFile, file_id, skip_tekoa_id: true).mime == "image/jpeg"
      assert rendition_count() == 1
      assert file_count(ctx.tekoa) == 1
      assert mural_count(ctx.tekoa) == 1

      assert {:error, :staging_missing} =
               Uploads.with_staged_file(completed, fn _path -> :unexpected end)

      assert :ok = Ingest.perform(job(upload, 2))
      assert_receive {:ybira_upload, ^public_id, :completed}

      assert rendition_count() == 1
      assert file_count(ctx.tekoa) == 1
      assert mural_count(ctx.tekoa) == 1
      assert Repo.get!(Tekoa, ctx.tekoa.id, skip_tekoa_id: true).storage_used_bytes == completed.size
    end)
  end

  test "preserves the selected folder hierarchy", ctx do
    {:ok, destination} = Ybira.create_folder(ctx.scope, %{name: "Destino"})

    upload =
      stage(ctx, text_file(ctx, "junho.txt", "ata de junho"), "junho.txt", %{
        folder_rkey: destination.rkey,
        relative_path: "Atas/2026/junho.txt"
      })

    assert :ok = Ingest.perform(job(upload, 1))
    assert {:ok, %Upload{state: :completed}} = Uploads.fetch_for_job(upload.public_id)
    assert {:ok, %{folders: [atas], files: []}} = Ybira.list_folder_contents(ctx.scope, destination.rkey)
    assert {:ok, %{folders: [ano], files: []}} = Ybira.list_folder_contents(ctx.scope, atas.rkey)
    assert {:ok, %{folders: [], files: [file]}} = Ybira.list_folder_contents(ctx.scope, ano.rkey)
    assert file.nome == "junho.txt"
  end

  test "purging a completed file preserves upload history without a foreign-key failure", ctx do
    upload = stage(ctx, text_file(ctx, "purge.txt", "purge me"), "purge.txt")
    assert :ok = Ingest.perform(job(upload, 1))

    assert {:ok, %Upload{state: :completed, file_id: file_id} = completed} =
             Uploads.fetch_for_job(upload.public_id)

    file = Repo.get!(YbiraFile, file_id, skip_tekoa_id: true)
    assert {:ok, _trashed} = Ybira.delete_file(ctx.scope, file.rkey)
    assert {:ok, _purged} = Ybira.purge_trash_file(ctx.scope, file.rkey)

    assert {:ok, %Upload{state: :completed, file_id: nil}} =
             Uploads.fetch_for_job(completed.public_id)
  end

  test "missing staging is terminal and leaves a safe failure code", ctx do
    Oban.Testing.with_testing_mode(:manual, fn ->
      :ok = Uploads.subscribe(ctx.scope)
      upload = stage(ctx, text_file(ctx, "missing.txt", "missing bytes"), "missing.txt")
      assert_receive {:ybira_upload, public_id, :queued}

      # The staging path is derived from the generated upload UUID.
      # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
      File.rm!(staged_path(upload))

      assert {:cancel, :staging_missing} = Ingest.perform(job(upload, 1))
      assert_receive {:ybira_upload, ^public_id, :processing}
      assert_receive {:ybira_upload, ^public_id, :failed}

      assert {:ok, %Upload{state: :failed, error_code: :staging_missing}} =
               Uploads.fetch_for_job(upload.public_id)

      assert file_count(ctx.tekoa) == 0
    end)
  end

  test "a disallowed MIME is cancelled with a safe terminal code", ctx do
    Oban.Testing.with_testing_mode(:manual, fn ->
      executable = <<0x4D, 0x5A, 0x90, 0x00, "not an image">>
      upload = stage(ctx, text_file(ctx, "disguised.jpg", executable), "disguised.jpg")

      assert {:cancel, :invalid_mime} = Ingest.perform(job(upload, 1))

      assert {:ok, %Upload{state: :failed, error_code: :invalid_mime}} =
               Uploads.fetch_for_job(upload.public_id)

      assert file_count(ctx.tekoa) == 0
      refute File.exists?(staged_path(upload))
    end)
  end

  test "final commit rejects an owner deactivated after the initial check", ctx do
    contents = "deactivated between validation and commit"
    upload = stage(ctx, text_file(ctx, "deactivated.txt", contents), "deactivated.txt")

    result =
      perform_at_final_commit(upload, contents, fn ->
        assert {:ok, _owner} =
                 Repo.with_tekoa(ctx.tekoa.public_id, fn ->
                   ava = Repo.get!(Ava, ctx.owner.id)

                   ava
                   |> Ava.deactivation_changeset(DateTime.truncate(DateTime.utc_now(), :second))
                   |> Repo.update()
                 end)
      end)

    assert result == {:cancel, :owner_inactive}

    assert {:ok, %Upload{state: :failed, error_code: :owner_inactive}} =
             Uploads.fetch_for_job(upload.public_id)

    assert file_count(ctx.tekoa) == 0
    assert Repo.get!(Tekoa, ctx.tekoa.id, skip_tekoa_id: true).storage_used_bytes == 0
  end

  test "final commit rejects a foreign destination folder", ctx do
    foreign_owner = active_ava_fixture(ctx.tekoa)

    {:ok, folder} =
      foreign_owner
      |> Scope.new(ctx.tekoa)
      |> Ybira.create_folder(%{name: "foreign"})

    contents = "file for a foreign folder"

    upload =
      stage(ctx, text_file(ctx, "foreign-folder.txt", contents), "foreign-folder.txt", %{
        folder_rkey: folder.rkey
      })

    mural_before = mural_count(ctx.tekoa)
    result = perform_at_final_commit(upload, contents, fn -> :ok end)

    assert result == {:cancel, :folder_unavailable}

    assert {:ok, %Upload{state: :failed, error_code: :folder_unavailable}} =
             Uploads.fetch_for_job(upload.public_id)

    assert file_count(ctx.tekoa) == 0
    assert mural_count(ctx.tekoa) == mural_before
    assert Repo.get!(Tekoa, ctx.tekoa.id, skip_tekoa_id: true).storage_used_bytes == 0
  end

  test "transient rendition enqueue failures requeue, retain staging, then fail on the last attempt", ctx do
    Oban.Testing.with_testing_mode(:manual, fn ->
      Repo.query!("""
      CREATE TEMP TRIGGER reject_ingest_rendition BEFORE INSERT ON oban_jobs
      WHEN NEW.worker = 'Taina.Ybira.Workers.Rendition'
      BEGIN SELECT RAISE(ABORT, 'forced rendition failure'); END
      """)

      upload = stage(ctx, image_file(ctx, "retry.jpg"), "retry.jpg")

      assert {:error, :processing_failed} = Ingest.perform(job(upload, 1))
      assert {:ok, %Upload{state: :queued}} = Uploads.fetch_for_job(upload.public_id)
      assert File.exists?(staged_path(upload))
      assert file_count(ctx.tekoa) == 0

      assert {:error, :processing_failed} = Ingest.perform(job(upload, 2))
      assert {:ok, %Upload{state: :queued}} = Uploads.fetch_for_job(upload.public_id)
      assert File.exists?(staged_path(upload))
      assert file_count(ctx.tekoa) == 0

      assert {:error, :processing_failed} = Ingest.perform(job(upload, 3))

      assert {:ok, %Upload{state: :failed, error_code: :processing_failed}} =
               Uploads.fetch_for_job(upload.public_id)

      refute File.exists?(staged_path(upload))
      assert file_count(ctx.tekoa) == 0
      assert rendition_count() == 0
    end)
  end

  test "stops admitting uploads at the active-row cap", ctx do
    for _index <- 1..20, do: pending_upload(ctx, 1)

    source = text_file(ctx, "row-cap.txt", "x")

    assert {:error, :storage_quota_exceeded} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{filename: "row-cap.txt", size: 1})

    assert pending_upload_count(ctx.tekoa) == 20
  end

  test "bounds active bytes when community quota is unlimited", ctx do
    previous_upload_config = Application.get_env(:taina, :upload, [])
    Application.put_env(:taina, :upload, Keyword.put(previous_upload_config, :max_blob_size, 10))

    on_exit(fn -> Application.put_env(:taina, :upload, previous_upload_config) end)

    Repo.update!(Ecto.Changeset.change(ctx.tekoa, storage_quota_bytes: nil))
    pending_upload(ctx, 20)
    source = text_file(ctx, "byte-cap.txt", "x")

    assert {:error, :storage_quota_exceeded} =
             Uploads.stage_and_enqueue(ctx.scope, source, %{filename: "byte-cap.txt", size: 1})

    assert pending_upload_count(ctx.tekoa) == 1
  end

  defp stage(ctx, source, filename, extra_attrs \\ %{}) do
    {:ok, %{size: size}} = File.stat(source)

    attrs = Map.merge(%{filename: filename, size: size}, extra_attrs)

    assert {:ok, upload} = Uploads.stage_and_enqueue(ctx.scope, source, attrs)

    upload
  end

  defp text_file(ctx, name, contents) do
    File.mkdir_p!(ctx.source_root)
    path = Path.join(ctx.source_root, name)
    # The fixture names above are fixed test inputs.
    # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
    File.write!(path, contents)
    path
  end

  defp image_file(ctx, name) do
    File.mkdir_p!(ctx.source_root)
    path = Path.join(ctx.source_root, name)
    {:ok, image} = Image.new(24, 16, color: [255, 0, 0])
    {:ok, _image} = Image.write(image, path)
    path
  end

  defp job(upload, attempt) do
    %Oban.Job{
      id: upload.oban_job_id,
      args: %{"upload_id" => upload.public_id},
      attempt: attempt,
      max_attempts: 3
    }
  end

  defp perform_at_final_commit(upload, contents, while_locked) do
    cid = contents |> Cid.from_data(Cid.raw()) |> Cid.to_string()
    parent = self()
    job = job(upload, 1)

    {worker, monitor} =
      spawn_monitor(fn ->
        receive do
          :perform -> send(parent, {:ingest_result, Ingest.perform(job)})
        end
      end)

    :erlang.trace(worker, true, [:send])

    BlobLock.run(cid, fn ->
      send(worker, :perform)
      assert_receive {:trace, ^worker, :send, {:"$gen_call", _from, {:lock, ^cid}}, _server}
      while_locked.()
    end)

    assert_receive {:ingest_result, result}
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    result
  end

  defp upload_job(upload), do: Repo.get!(Oban.Job, upload.oban_job_id)

  defp pending_upload(ctx, size) do
    public_id = Ecto.UUID.generate()

    %Upload{tekoa_id: ctx.tekoa.id, dono_id: ctx.owner.id}
    |> Upload.changeset(%{
      public_id: public_id,
      filename: "pending-#{public_id}.bin",
      size: size,
      staging_key: "staging/uploads/#{public_id}",
      state: :queued
    })
    |> Repo.insert!()
  end

  defp staged_path(upload) do
    Path.join([Application.fetch_env!(:taina, :storage_root), upload.staging_key])
  end

  defp pending_upload_count(tekoa) do
    {:ok, count} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        count =
          Repo.aggregate(
            from(upload in Upload,
              where: upload.tekoa_id == ^tekoa.id and upload.state in [:queued, :processing]
            ),
            :count,
            :id
          )

        {:ok, count}
      end)

    count
  end

  defp file_count(tekoa) do
    {:ok, count} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok, Repo.aggregate(YbiraFile, :count, :id)}
      end)

    count
  end

  defp mural_count(tekoa) do
    {:ok, entries} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok, MuralStore.cadeia(Repo, tekoa.id)}
      end)

    length(entries)
  end

  defp rendition_count do
    Repo.aggregate(
      from(job in Oban.Job, where: job.worker == ^inspect(Rendition)),
      :count,
      :id
    )
  end
end
