defmodule Taina.YbiraTest do
  use Taina.DataCase, async: false

  import Taina.Fixtures

  alias Taina.Maraca.Tekoa
  alias Taina.Ybira

  describe "upload/3" do
    test "stores the file on disk, inserts the record and updates usage" do
      scope = scope_fixture()
      tmp = tmp_upload_fixture("olá ybira", "ferias.txt")

      assert {:ok, file} = Ybira.upload(scope, tmp, filename: "minhas_ferias.txt")

      assert file.original_filename == "minhas_ferias.txt"
      assert file.mime_type == "text/plain"
      assert file.file_size_bytes == byte_size("olá ybira")
      assert String.length(file.public_id) == 12
      assert file.file_hash == :sha256 |> :crypto.hash("olá ybira") |> Base.encode16(case: :lower)
      assert File.exists?(file.filepath)
      assert file.filepath =~ scope.tekoa.public_id

      tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == file.file_size_bytes
    end

    test "rejects upload beyond the tekoa quota" do
      tekoa = tekoa_fixture(%{storage_quota_bytes: 4})
      ava = ava_fixture(tekoa)
      scope = Taina.Scope.new(ava, tekoa)
      tmp = tmp_upload_fixture("mais que quatro bytes")

      assert {:error, :storage_quota_exceeded} = Ybira.upload(scope, tmp)

      tekoa = Repo.get!(Tekoa, tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == 0
    end

    test "returns error for a missing temporary file" do
      scope = scope_fixture()

      assert {:error, :enoent} = Ybira.upload(scope, "/tmp/nao_existe_#{System.unique_integer()}")
    end
  end

  describe "get_file/2" do
    test "finds a file by public_id within the scope's tekoa" do
      scope = scope_fixture()
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:ok, found} = Ybira.get_file(scope, file.public_id)
      assert found.id == file.id
    end

    test "returns not_found for unknown public_id" do
      scope = scope_fixture()

      assert {:error, :not_found} = Ybira.get_file(scope, "desconhecido1")
    end
  end

  describe "list_files/2" do
    test "lists root files, newest first" do
      scope = scope_fixture()
      {:ok, _a} = Ybira.upload(scope, tmp_upload_fixture("a", "a.txt"))
      {:ok, b} = Ybira.upload(scope, tmp_upload_fixture("b", "b.txt"))

      assert {:ok, files} = Ybira.list_files(scope)
      assert length(files) == 2
      assert hd(files).id == b.id
    end

    test "returns an empty list when there are no files" do
      scope = scope_fixture()

      assert {:ok, []} = Ybira.list_files(scope)
    end
  end

  describe "delete_file/2" do
    test "removes record and bytes, and decrements usage" do
      scope = scope_fixture()
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:ok, deleted} = Ybira.delete_file(scope, file.public_id)
      assert deleted.id == file.id
      refute File.exists?(file.filepath)
      assert {:error, :not_found} = Ybira.get_file(scope, file.public_id)

      tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == 0
    end

    test "only the owner can delete" do
      scope = scope_fixture()
      other = ava_fixture(scope.tekoa)
      other_scope = Taina.Scope.new(other, scope.tekoa)
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:error, :not_found} = Ybira.delete_file(other_scope, file.public_id)
      assert {:ok, _} = Ybira.get_file(scope, file.public_id)
    end
  end

  describe "prepare_query guard" do
    test "raises when querying tenant tables outside with_tekoa" do
      assert_raise RuntimeError, ~r/fora do contexto de Tekoa/, fn ->
        Repo.all(Ybira.File)
      end
    end

    test "allows system queries with skip_tekoa_id" do
      assert Repo.all(Ybira.File, skip_tekoa_id: true) == []
    end
  end

  describe "single-tekoa enforcement" do
    test "refuses a second tekoa at the database level" do
      tekoa_fixture()

      changeset = Tekoa.changeset(%Tekoa{}, %{name: "Segunda Tekoa", storage_quota_bytes: 1024})

      assert {:error, changeset} = Repo.insert(changeset)
      assert "apenas uma Tekoa por instância (ver RFC 002, D2)" in errors_on(changeset).name
    end
  end
end
