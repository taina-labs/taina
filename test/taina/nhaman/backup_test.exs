defmodule Taina.Nhaman.BackupTest do
  use ExUnit.Case, async: true

  alias Taina.Nhaman.Backup
  alias Taina.Nhaman.Workers.Backup, as: BackupWorker

  describe "pure builders" do
    test "archive_filename/1 stamps UTC seconds" do
      {:ok, dt, 0} = DateTime.from_iso8601("2026-06-10T13:05:09Z")
      assert Backup.archive_filename(dt) == "taina-backup-20260610T130509Z.tar.gz"
    end

    test "pg_dump_args/2 uses custom format and target file" do
      args = Backup.pg_dump_args("postgresql://u@h/db", "/tmp/db.dump")

      assert "--format=custom" in args
      assert "--file=/tmp/db.dump" in args
      assert "--dbname=postgresql://u@h/db" in args
    end

    test "pg_restore_args/2 cleans before reload and ends with the dump path" do
      args = Backup.pg_restore_args("postgresql://u@h/db", "/tmp/db.dump")

      assert "--clean" in args
      assert "--if-exists" in args
      assert List.last(args) == "/tmp/db.dump"
    end
  end

  describe "storage archive round-trip" do
    test "package, extract and restore put files back byte-for-byte" do
      storage = tmp_dir()
      nested = Path.join(storage, "tekoaA/files/2026/06")
      File.mkdir_p!(nested)
      File.write!(Path.join(nested, "x.txt"), "hello")
      File.write!(Path.join(storage, "root.txt"), "top")

      dump = Path.join(tmp_dir(), "db.dump")
      File.write!(dump, "FAKE DUMP")

      archive = Path.join(tmp_dir(), "backup.tar.gz")
      assert :ok = Backup.package_archive(archive, dump, storage)
      assert File.exists?(archive)

      extracted = tmp_dir()
      assert :ok = Backup.extract_archive(archive, extracted)
      assert File.read!(Path.join(extracted, "db.dump")) == "FAKE DUMP"
      assert File.read!(Path.join(extracted, "storage/tekoaA/files/2026/06/x.txt")) == "hello"
      assert File.read!(Path.join(extracted, "storage/root.txt")) == "top"

      dest = Path.join(tmp_dir(), "restored")
      assert :ok = Backup.restore_storage(Path.join(extracted, "storage"), dest)
      assert File.read!(Path.join(dest, "tekoaA/files/2026/06/x.txt")) == "hello"
      assert File.read!(Path.join(dest, "root.txt")) == "top"
    end

    test "restore_storage replaces prior contents" do
      src = tmp_dir()
      File.write!(Path.join(src, "keep.txt"), "new")

      dest = tmp_dir()
      File.write!(Path.join(dest, "stale.txt"), "old")

      assert :ok = Backup.restore_storage(src, dest)
      assert File.read!(Path.join(dest, "keep.txt")) == "new"
      refute File.exists?(Path.join(dest, "stale.txt"))
    end

    test "package handles an absent storage root" do
      dump = Path.join(tmp_dir(), "db.dump")
      File.write!(dump, "D")
      archive = Path.join(tmp_dir(), "b.tar.gz")

      assert :ok = Backup.package_archive(archive, dump, Path.join(tmp_dir(), "missing"))

      extracted = tmp_dir()
      assert :ok = Backup.extract_archive(archive, extracted)
      assert File.read!(Path.join(extracted, "db.dump")) == "D"
      refute File.exists?(Path.join(extracted, "storage"))
    end
  end

  describe "scheduled worker" do
    test "is a no-op while backup is disabled (the default)" do
      refute Backup.enabled?()
      assert :ok = BackupWorker.perform(%Oban.Job{args: %{}})
    end
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "taina_backup_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
