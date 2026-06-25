defmodule Taina.YbiraTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Maraca.Tekoa
  alias Taina.Scope
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
      scope = Scope.new(ava, tekoa)
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

  describe "list_files/3" do
    test "lists root files, newest first" do
      scope = scope_fixture()
      {:ok, _a} = Ybira.upload(scope, tmp_upload_fixture("a", "a.txt"))
      {:ok, b} = Ybira.upload(scope, tmp_upload_fixture("b", "b.txt"))

      assert {:ok, %{items: files, next_cursor: nil}} = Ybira.list_files(scope)
      assert length(files) == 2
      assert hd(files).id == b.id
    end

    test "returns an empty page when there are no files" do
      scope = scope_fixture()

      assert {:ok, %{items: [], next_cursor: nil}} = Ybira.list_files(scope)
    end

    test "paginates with an opaque keyset cursor" do
      scope = scope_fixture()
      {:ok, a} = Ybira.upload(scope, tmp_upload_fixture("a", "a.txt"))
      {:ok, b} = Ybira.upload(scope, tmp_upload_fixture("b", "b.txt"))
      {:ok, c} = Ybira.upload(scope, tmp_upload_fixture("c", "c.txt"))

      assert {:ok, %{items: [first, second], next_cursor: cursor}} =
               Ybira.list_files(scope, nil, limit: 2)

      assert [first.id, second.id] == [c.id, b.id]
      assert is_binary(cursor)

      assert {:ok, %{items: [third], next_cursor: nil}} =
               Ybira.list_files(scope, nil, limit: 2, after_cursor: cursor)

      assert third.id == a.id
    end
  end

  describe "delete_file/2 (soft delete)" do
    test "moves the file to trash, keeps bytes on disk and quota unchanged" do
      scope = scope_fixture()
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:ok, deleted} = Ybira.delete_file(scope, file.public_id)
      assert deleted.id == file.id
      assert deleted.deleted_at
      assert File.exists?(file.filepath)
      assert {:error, :not_found} = Ybira.get_file(scope, file.public_id)
      assert {:ok, %{items: []}} = Ybira.list_files(scope)

      tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == file.file_size_bytes
    end

    test "only the owner can delete" do
      scope = scope_fixture()
      other = ava_fixture(scope.tekoa)
      other_scope = Scope.new(other, scope.tekoa)
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:error, :not_found} = Ybira.delete_file(other_scope, file.public_id)
      assert {:ok, _} = Ybira.get_file(scope, file.public_id)
    end
  end

  describe "restore_file/2 and list_trash/2" do
    test "trashed file shows in trash, not in listing, and can be restored" do
      scope = scope_fixture()
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())
      {:ok, _} = Ybira.delete_file(scope, file.public_id)

      assert {:ok, %{items: [trashed]}} = Ybira.list_trash(scope)
      assert trashed.id == file.id
      assert {:ok, %{items: []}} = Ybira.list_files(scope)

      assert {:ok, restored} = Ybira.restore_file(scope, file.public_id)
      refute restored.deleted_at
      assert {:ok, %{items: [back]}} = Ybira.list_files(scope)
      assert back.id == file.id
      assert {:ok, %{items: []}} = Ybira.list_trash(scope)
    end

    test "restore returns not_found for a file that is not trashed" do
      scope = scope_fixture()
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:error, :not_found} = Ybira.restore_file(scope, file.public_id)
    end
  end

  describe "upload/3 MIME detection (magic bytes)" do
    # PNG magic bytes sem corpo válido: o rendition inline falha ao abrir e loga.
    @tag capture_log: true
    test "detects PNG by magic bytes regardless of extension" do
      scope = scope_fixture()
      png = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0>>
      tmp = tmp_upload_fixture(png, "nao_eh_texto.txt")

      assert {:ok, file} = Ybira.upload(scope, tmp)
      assert file.mime_type == "image/png"
    end

    test "detects PDF by magic bytes" do
      scope = scope_fixture()
      tmp = tmp_upload_fixture("%PDF-1.7\n...", "doc.bin")

      assert {:ok, file} = Ybira.upload(scope, tmp)
      assert file.mime_type == "application/pdf"
    end

    test "rejects executables disguised with an allowed extension" do
      scope = scope_fixture()
      # Cabeçalho "MZ" de um executável Windows, com extensão .jpg.
      tmp = tmp_upload_fixture(<<0x4D, 0x5A, 0x90, 0x00, "rest">>, "foto.jpg")

      assert {:error, :mime_not_allowed} = Ybira.upload(scope, tmp)
      tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == 0
    end
  end

  describe "folder CRUD" do
    test "creates, renames and nests folders" do
      scope = scope_fixture()

      assert {:ok, parent} = Ybira.create_folder(scope, %{name: "Documentos"})
      assert parent.name == "Documentos"
      assert is_nil(parent.parent_id)

      assert {:ok, child} =
               Ybira.create_folder(scope, %{name: "Fotos", parent_public_id: parent.public_id})

      assert child.parent_id == parent.id

      assert {:ok, renamed} = Ybira.rename_folder(scope, parent.public_id, "Arquivo")
      assert renamed.name == "Arquivo"

      assert {:ok, found} = Ybira.get_folder(scope, parent.public_id)
      assert found.name == "Arquivo"
    end

    test "create_folder with an unknown parent returns not_found" do
      scope = scope_fixture()

      assert {:error, :not_found} =
               Ybira.create_folder(scope, %{name: "x", parent_public_id: "naoexiste12"})
    end

    test "move_folder rejects circular references" do
      scope = scope_fixture()
      {:ok, parent} = Ybira.create_folder(scope, %{name: "pai"})
      {:ok, child} = Ybira.create_folder(scope, %{name: "filho", parent_public_id: parent.public_id})

      assert {:error, :circular_reference} =
               Ybira.move_folder(scope, parent.public_id, child.public_id)

      assert {:error, :circular_reference} =
               Ybira.move_folder(scope, parent.public_id, parent.public_id)
    end

    test "delete_folder soft-deletes the folder, its files and subfolders" do
      scope = scope_fixture()
      {:ok, parent} = Ybira.create_folder(scope, %{name: "pai"})
      {:ok, child} = Ybira.create_folder(scope, %{name: "filho", parent_public_id: parent.public_id})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("x", "x.txt"), folder_id: child.id)

      assert {:ok, :deleted} = Ybira.delete_folder(scope, parent.public_id)

      assert {:error, :not_found} = Ybira.get_folder(scope, parent.public_id)
      assert {:error, :not_found} = Ybira.get_folder(scope, child.public_id)
      assert {:error, :not_found} = Ybira.get_file(scope, file.public_id)
      # Bytes ficam no disco até o PurgeTrash (não recupera cota agora).
      assert File.exists?(file.filepath)
    end
  end

  describe "move_file/3 and list_folder_contents/3" do
    test "moves a file into a folder and lists folder contents" do
      scope = scope_fixture()
      {:ok, folder} = Ybira.create_folder(scope, %{name: "destino"})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("x", "x.txt"))

      assert {:ok, moved} = Ybira.move_file(scope, file.public_id, folder.public_id)
      assert moved.folder_id == folder.id

      assert {:ok, %{folders: [], files: [listed], next_cursor: nil}} =
               Ybira.list_folder_contents(scope, folder.public_id)

      assert listed.id == file.id

      # Saiu da raiz.
      assert {:ok, %{items: []}} = Ybira.list_files(scope)
    end

    test "root listing shows folders and paginates files" do
      scope = scope_fixture()
      {:ok, _folder} = Ybira.create_folder(scope, %{name: "uma pasta"})
      {:ok, _a} = Ybira.upload(scope, tmp_upload_fixture("a", "a.txt"))
      {:ok, _b} = Ybira.upload(scope, tmp_upload_fixture("b", "b.txt"))
      {:ok, _c} = Ybira.upload(scope, tmp_upload_fixture("c", "c.txt"))

      assert {:ok, %{folders: [folder], files: files, next_cursor: cursor}} =
               Ybira.list_folder_contents(scope, nil, limit: 2)

      assert folder.name == "uma pasta"
      assert length(files) == 2
      # Paginação por offset: next_cursor é o próximo deslocamento (inteiro).
      assert cursor == 2

      assert {:ok, %{files: [_last], next_cursor: nil}} =
               Ybira.list_folder_contents(scope, nil, limit: 2, offset: cursor)
    end
  end

  describe "storage_stats/1" do
    test "reports used and quota bytes for the tekoa" do
      tekoa = tekoa_fixture(%{storage_quota_bytes: 1000})
      ava = ava_fixture(tekoa)
      scope = Scope.new(ava, tekoa)
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("12345", "n.txt"))

      assert {:ok, %{used_bytes: used, quota_bytes: 1000}} = Ybira.storage_stats(scope)
      assert used == file.file_size_bytes
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

  # --- ZEETECH-69: zonas casa/praca ---

  # Tres avas ativos numa unica Tekoa: A (dono), B (outro morador), Z (zelador).
  defp three_avas do
    tekoa = tekoa_fixture()
    a = active_ava_fixture(tekoa)
    b = active_ava_fixture(tekoa)
    z = zelador_fixture(tekoa)
    {tekoa, Scope.new(a, tekoa), Scope.new(b, tekoa), Scope.new(z, tekoa)}
  end

  describe "zona padrao" do
    test "a new file starts in :casa" do
      {_tekoa, a, _b, _z} = three_avas()

      assert {:ok, file} = Ybira.upload(a, tmp_upload_fixture())
      assert file.zona == :casa
    end
  end

  describe "publicar_file/2 e tirar_file_da_praca/2" do
    test "round-trip casa -> praca -> casa" do
      {_tekoa, a, _b, _z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:ok, %{zona: :praca}} = Ybira.publicar_file(a, file.public_id)
      assert {:ok, %{zona: :casa}} = Ybira.tirar_file_da_praca(a, file.public_id)
    end

    test "only the owner can publish; another morador and the zelador get not_found" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:error, :not_found} = Ybira.publicar_file(b, file.public_id)
      assert {:error, :not_found} = Ybira.publicar_file(z, file.public_id)
    end

    test "publishing is idempotent" do
      {_tekoa, a, _b, _z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:ok, %{zona: :praca}} = Ybira.publicar_file(a, file.public_id)
      assert {:ok, %{zona: :praca}} = Ybira.publicar_file(a, file.public_id)
    end
  end

  describe "publicar_folder/2 e tirar_folder_da_praca/2" do
    test "round-trip and owner-gating" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "publica"})

      assert {:ok, %{zona: :praca}} = Ybira.publicar_folder(a, folder.public_id)
      assert {:ok, %{zona: :casa}} = Ybira.tirar_folder_da_praca(a, folder.public_id)

      assert {:error, :not_found} = Ybira.publicar_folder(b, folder.public_id)
      assert {:error, :not_found} = Ybira.publicar_folder(z, folder.public_id)
    end

    test "publishing a folder does not cascade to its children" do
      {_tekoa, a, _b, _z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "album"})
      {:ok, child} = Ybira.upload(a, tmp_upload_fixture(), folder_id: folder.id)

      assert {:ok, %{zona: :praca}} = Ybira.publicar_folder(a, folder.public_id)

      assert {:ok, refetched} = Ybira.get_file(a, child.public_id)
      assert refetched.zona == :casa
    end
  end

  describe "move_file/3 keeps zona" do
    test "moving a casa file into a praca folder leaves the file in :casa" do
      {_tekoa, a, _b, _z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "destino"})
      {:ok, _} = Ybira.publicar_folder(a, folder.public_id)
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:ok, moved} = Ybira.move_file(a, file.public_id, folder.public_id)
      assert moved.zona == :casa
    end
  end

  # --- ZEETECH-70: regra de leitura das duas zonas ---

  describe "read rule across zones" do
    test "praca item is readable by any morador and the zelador" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Ybira.publicar_file(a, file.public_id)

      assert {:ok, _} = Ybira.get_file(b, file.public_id)
      assert {:ok, _} = Ybira.get_file(z, file.public_id)

      assert file.public_id in listed_file_ids(Ybira.list_files(b))
      assert file.public_id in listed_file_ids(Ybira.list_files(z))
      assert file.public_id in recent_ids(Ybira.list_recent(b))
    end

    test "casa item is readable only by the owner" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:ok, _} = Ybira.get_file(a, file.public_id)
      assert file.public_id in listed_file_ids(Ybira.list_files(a))

      assert {:error, :forbidden} = Ybira.get_file(b, file.public_id)
      assert {:error, :forbidden} = Ybira.get_file(z, file.public_id)

      refute file.public_id in listed_file_ids(Ybira.list_files(b))
      refute file.public_id in listed_file_ids(Ybira.list_files(z))
    end

    test "casa item is readable by an Ava with an explicit :read grant" do
      {tekoa, a, b, _z} = three_avas()
      c = Scope.new(active_ava_fixture(tekoa), tekoa)
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      {:ok, _} = Maraca.grant_permission(a.ava, b.ava, :read, "ybira_file", file.public_id)

      assert {:ok, _} = Ybira.get_file(b, file.public_id)
      assert file.public_id in listed_file_ids(Ybira.list_files(b))

      assert {:error, :forbidden} = Ybira.get_file(c, file.public_id)
      refute file.public_id in listed_file_ids(Ybira.list_files(c))
    end

    test "the zelador has no shortcut into another resident's casa" do
      {_tekoa, a, _b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:error, :forbidden} = Ybira.get_file(z, file.public_id)

      refute file.public_id in listed_file_ids(Ybira.list_files(z))
      refute file.public_id in recent_ids(Ybira.list_recent(z))

      {:ok, %{files: files}} = Ybira.list_folder_contents(z)
      refute file.public_id in Enum.map(files, & &1.public_id)
    end

    test ":forbidden is distinct from :not_found" do
      {_tekoa, a, b, _z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:error, :forbidden} = Ybira.get_file(b, file.public_id)
      assert {:error, :not_found} = Ybira.get_file(b, "inexistente12")
    end

    test "casa folder is hidden from other moradores in list_folders" do
      {_tekoa, a, b, _z} = three_avas()
      {:ok, casa} = Ybira.create_folder(a, %{name: "privada"})
      {:ok, praca} = Ybira.create_folder(a, %{name: "publica"})
      {:ok, _} = Ybira.publicar_folder(a, praca.public_id)

      {:ok, folders} = Ybira.list_folders(b)
      ids = Enum.map(folders, & &1.public_id)
      assert praca.public_id in ids
      refute casa.public_id in ids
    end

    test "a praca folder does not leak its casa children when another morador lists it" do
      {_tekoa, a, b, _z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "album"})
      {:ok, _} = Ybira.publicar_folder(a, folder.public_id)
      {:ok, child} = Ybira.upload(a, tmp_upload_fixture(), folder_id: folder.id)

      {:ok, %{files: files}} = Ybira.list_folder_contents(b, folder.public_id)
      refute child.public_id in Enum.map(files, & &1.public_id)
    end
  end

  defp listed_file_ids({:ok, %{items: items}}), do: Enum.map(items, & &1.public_id)
  defp recent_ids({:ok, files}), do: Enum.map(files, & &1.public_id)

  # --- ZEETECH-71: alvo do pedido de acesso (RFC_003 D4) ---

  describe "fetch_access_target/2" do
    test "forbidden casa returns the owner, file id and filename" do
      {tekoa, a, b, _z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture("oi", "particular.txt"))

      assert {:ok, target} = Ybira.fetch_access_target(b, file.public_id)
      assert target.owner.id == a.ava.id
      assert target.file_public_id == file.public_id
      assert target.filename == "particular.txt"
      # `request_access/5` precisa do dono com a Tekoa carregada.
      assert %Tekoa{id: tekoa_id} = target.owner.tekoa
      assert tekoa_id == tekoa.id
    end

    test "praca, own and granted files are already readable" do
      {tekoa, a, b, _z} = three_avas()
      c = Scope.new(active_ava_fixture(tekoa), tekoa)

      {:ok, praca} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Ybira.publicar_file(a, praca.public_id)
      assert {:error, :already_readable} = Ybira.fetch_access_target(b, praca.public_id)

      {:ok, own} = Ybira.upload(a, tmp_upload_fixture())
      assert {:error, :already_readable} = Ybira.fetch_access_target(a, own.public_id)

      {:ok, granted} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Maraca.grant_permission(a.ava, c.ava, :read, "ybira_file", granted.public_id)
      assert {:error, :already_readable} = Ybira.fetch_access_target(c, granted.public_id)
    end

    test "missing and deleted files are not found" do
      {_tekoa, a, b, _z} = three_avas()

      assert {:error, :not_found} = Ybira.fetch_access_target(b, "inexistente12")

      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Ybira.delete_file(a, file.public_id)
      assert {:error, :not_found} = Ybira.fetch_access_target(b, file.public_id)
    end
  end
end
