defmodule Taina.Nhaman.BackupTest do
  # These tests change application-wide config and create temporary filesystem state.
  use ExUnit.Case, async: false

  import Bitwise

  alias Taina.Nhaman.Backup
  alias Taina.Nhaman.Workers.Backup, as: BackupWorker

  describe "pure builders" do
    test "archive_filename/1 stamps UTC seconds" do
      {:ok, dt, 0} = DateTime.from_iso8601("2026-06-10T13:05:09Z")
      assert Backup.archive_filename(dt) == "taina-backup-20260610T130509Z.tar.gz"
    end
  end

  describe "storage archive round-trip" do
    test "package, extract and restore put files back byte-for-byte" do
      storage = temporary_directory()
      nested = Path.join(storage, "tekoaA/files/2026/06")
      File.mkdir_p!(nested)
      File.write!(Path.join(nested, "x.txt"), "hello")
      File.write!(Path.join(storage, "root.txt"), "top")

      dump = Path.join(temporary_directory(), "db.dump")
      File.write!(dump, "FAKE DUMP")
      secret = Path.join(temporary_directory(), "secret_key_base")
      File.write!(secret, "test-secret")

      archive = Path.join(temporary_directory(), "backup.tar.gz")
      assert :ok = Backup.package_archive(archive, dump, storage, secret)
      assert File.exists?(archive)

      extracted = temporary_directory()
      assert :ok = Backup.extract_archive(archive, extracted)
      assert File.read!(Path.join(extracted, "db.dump")) == "FAKE DUMP"
      assert File.read!(Path.join(extracted, "storage/tekoaA/files/2026/06/x.txt")) == "hello"
      assert File.read!(Path.join(extracted, "storage/root.txt")) == "top"

      dest = Path.join(temporary_directory(), "restored")
      assert :ok = Backup.restore_storage(Path.join(extracted, "storage"), dest)
      assert File.read!(Path.join(dest, "tekoaA/files/2026/06/x.txt")) == "hello"
      assert File.read!(Path.join(dest, "root.txt")) == "top"
    end

    test "backup and restore round-trip the persistent secret" do
      root = temporary_directory()
      storage = Path.join(root, "storage")
      File.mkdir_p!(storage)
      File.write!(Path.join(storage, "file.txt"), "new")
      dump = Path.join(root, "db.dump")
      File.write!(dump, "new-db")
      secret = Path.join(root, "secret_key_base")
      File.write!(secret, "persistent-secret")
      archive = Path.join(root, "backup.tar.gz")
      db = Path.join(root, "taina.db")
      restored_storage = Path.join(root, "restored-storage")
      restored_secret = Path.join(root, "restored/secret_key_base")
      File.write!(db, "old-db")
      File.mkdir_p!(restored_storage)
      File.write!(Path.join(restored_storage, "old.txt"), "old")

      Application.put_env(:taina, :config, %{
        data_dir: Path.dirname(restored_secret),
        secret_key_base_file: restored_secret
      })

      on_exit(fn -> Application.delete_env(:taina, :config) end)

      assert :ok = Backup.package_archive(archive, dump, storage, secret)
      assert {:ok, :restored} = Backup.restore(archive, storage_root: restored_storage, database_path: db)
      assert File.read!(db) == "new-db"
      assert File.read!(Path.join(restored_storage, "file.txt")) == "new"
      assert File.read!(restored_secret) == "persistent-secret"
      assert (File.stat!(restored_secret).mode &&& 0o777) == 0o600
    end

    test "restore rejects a missing secret before changing existing data" do
      root = temporary_directory()
      dump = Path.join(root, "db.dump")
      File.write!(dump, "new-db")
      archive = Path.join(root, "missing-secret.tar.gz")
      missing_secret = Path.join(root, "missing-secret")

      assert {:error, :missing_secret} =
               Backup.package_archive(archive, dump, Path.join(root, "missing-storage"), missing_secret)

      assert {:error, :missing_secret} =
               Backup.package_archive(archive, dump, Path.join(root, "missing-storage"))

      refute File.exists?(archive)

      # Old archives without a secret still fail restore validation.
      assert :ok =
               :erl_tar.create(
                 String.to_charlist(archive),
                 [{~C"db.dump", String.to_charlist(dump)}],
                 [:compressed]
               )

      db = Path.join(root, "taina.db")
      File.write!(db, "old-db")
      storage = Path.join(root, "storage")
      File.mkdir_p!(storage)
      File.write!(Path.join(storage, "old.txt"), "old")

      assert {:error, :missing_secret} = Backup.restore(archive, storage_root: storage, database_path: db)
      assert File.read!(db) == "old-db"
      assert File.read!(Path.join(storage, "old.txt")) == "old"
    end

    test "restore_storage replaces prior contents" do
      src = temporary_directory()
      File.write!(Path.join(src, "keep.txt"), "new")

      dest = temporary_directory()
      File.write!(Path.join(dest, "stale.txt"), "old")

      assert :ok = Backup.restore_storage(src, dest)
      assert File.read!(Path.join(dest, "keep.txt")) == "new"
      refute File.exists?(Path.join(dest, "stale.txt"))
    end

    test "package handles an absent storage root" do
      dump = Path.join(temporary_directory(), "db.dump")
      File.write!(dump, "D")
      archive = Path.join(temporary_directory(), "b.tar.gz")
      secret = Path.join(temporary_directory(), "secret_key_base")
      File.write!(secret, "test-secret")

      assert :ok = Backup.package_archive(archive, dump, Path.join(temporary_directory(), "missing"), secret)

      extracted = temporary_directory()
      assert :ok = Backup.extract_archive(archive, extracted)
      assert File.read!(Path.join(extracted, "db.dump")) == "D"
      refute File.exists?(Path.join(extracted, "storage"))
    end
  end

  test "run fails before creating an archive when the secret is missing" do
    root = temporary_directory()
    secret = Path.join(root, "missing-secret")
    previous = Application.get_env(:taina, :config)
    Application.put_env(:taina, :config, %{secret_key_base_file: secret})

    on_exit(fn ->
      if previous,
        do: Application.put_env(:taina, :config, previous),
        else: Application.delete_env(:taina, :config)
    end)

    {:ok, now, 0} = DateTime.from_iso8601("2026-06-10T13:05:09Z")
    archive = Path.join(root, Backup.archive_filename(now))

    assert {:error, :missing_secret} =
             Backup.run(
               dir: root,
               storage_root: Path.join(root, "storage"),
               database_path: Path.join(root, "missing.db"),
               now: now
             )

    refute File.exists?(archive)
  end

  describe "last_backup/0 e parse_archive_filename/1" do
    setup do
      original = Application.fetch_env!(:taina, :backup)
      on_exit(fn -> Application.put_env(:taina, :backup, original) end)
      :ok
    end

    test "parse decodifica o stamp que archive_filename/1 codifica" do
      {:ok, dt, 0} = DateTime.from_iso8601("2026-06-10T13:05:09Z")

      assert {:ok, ^dt} = Backup.parse_archive_filename("taina-backup-20260610T130509Z.tar.gz")
      assert Backup.parse_archive_filename(Backup.archive_filename(dt)) == {:ok, dt}
    end

    test "parse rejeita nome que não é do backup" do
      assert :error = Backup.parse_archive_filename("notas.txt")
      assert :error = Backup.parse_archive_filename("taina-backup-semtstamp.tar.gz")
      assert :error = Backup.parse_archive_filename("taina-backup-20261399T999999Z.tar.gz")
    end

    test "sem destino configurado" do
      Application.put_env(:taina, :backup, enabled: false, dir: nil)

      assert {:error, :no_dir} = Backup.last_backup()
    end

    test "destino existente e vazio: nenhum backup ainda" do
      Application.put_env(:taina, :backup, enabled: false, dir: temporary_directory())

      assert {:error, :none} = Backup.last_backup()
    end

    test "o mais recente entre os arquivos do destino, ignorando intrusos" do
      dir = temporary_directory()
      {:ok, recent, 0} = DateTime.from_iso8601("2026-10-04T04:00:00Z")
      {:ok, old, 0} = DateTime.from_iso8601("2026-10-01T04:00:00Z")

      File.write!(Path.join(dir, Backup.archive_filename(old)), "antigo")
      File.write!(Path.join(dir, Backup.archive_filename(recent)), "novo recente")
      File.write!(Path.join(dir, "notas-do-pendrive.txt"), "intruso")

      Application.put_env(:taina, :backup, enabled: false, dir: dir)

      assert {:ok, %{at: ^recent, bytes: bytes}} = Backup.last_backup()
      assert bytes == byte_size("novo recente")
    end

    test "destino que nunca existiu é 'nenhum backup'; caminho torto é ilegível" do
      Application.put_env(:taina, :backup, enabled: false, dir: temporary_directory() <> "/nunca_criado")

      assert {:error, :none} = Backup.last_backup()

      # Caminho que existe mas não é diretório: outra falha, não "vazio".
      file = Path.join(temporary_directory(), "arquivo-nao-diretorio")
      # The path is inside a test-owned temporary directory with a fixed filename.
      # credo:disable-for-next-line OeditusCredo.Check.Security.PathTraversal
      File.write!(file, "x")
      Application.put_env(:taina, :backup, enabled: false, dir: file)

      assert {:error, :unreadable} = Backup.last_backup()
    end
  end

  describe "scheduled worker" do
    test "is a no-op while backup is disabled (the default)" do
      refute Backup.enabled?()
      assert :ok = BackupWorker.perform(%Oban.Job{args: %{}})
    end
  end

  defp temporary_directory do
    dir = Path.join(System.tmp_dir!(), "taina_backup_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
