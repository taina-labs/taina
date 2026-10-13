defmodule Taina.YbiraTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira
  alias Ypy.Maraca.Tekoa

  describe "upload/3" do
    test "stores the file on disk, inserts the record and updates usage" do
      scope = scope_fixture()
      tmp = tmp_upload_fixture("olá ybira", "ferias.txt")

      assert {:ok, file} = Ybira.upload(scope, tmp, filename: "minhas_ferias.txt")

      assert file.nome == "minhas_ferias.txt"
      assert file.mime == "text/plain"
      assert file.tamanho == byte_size("olá ybira")
      assert String.length(file.rkey) == 13
      assert file.hash == :sha256 |> :crypto.hash("olá ybira") |> Base.encode16(case: :lower)

      # Os bytes ficam no BlobStore, endereçados pelo CID (layout blobs/).
      assert {:ok, path} = Ybira.blob_path(file)
      assert File.exists?(path)

      tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == file.tamanho
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

      assert {:ok, found} = Ybira.get_file(scope, file.rkey)
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

      assert {:ok, deleted} = Ybira.delete_file(scope, file.rkey)
      assert deleted.id == file.id
      assert deleted.apagado_em
      assert {:ok, path} = Ybira.blob_path(file)
      assert File.exists?(path)
      assert {:error, :not_found} = Ybira.get_file(scope, file.rkey)
      assert {:ok, %{items: []}} = Ybira.list_files(scope)

      tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == file.tamanho
    end

    test "only the owner can delete" do
      scope = scope_fixture()
      other = ava_fixture(scope.tekoa)
      other_scope = Scope.new(other, scope.tekoa)
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:error, :not_owner} = Ybira.delete_file(other_scope, file.rkey)
      assert {:ok, _} = Ybira.get_file(scope, file.rkey)
    end
  end

  describe "restore_file/2 and list_trash/2" do
    test "trashed file shows in trash, not in listing, and can be restored" do
      scope = scope_fixture()
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())
      {:ok, _} = Ybira.delete_file(scope, file.rkey)

      assert {:ok, %{items: [trashed]}} = Ybira.list_trash(scope)
      assert trashed.id == file.id
      assert {:ok, %{items: []}} = Ybira.list_files(scope)

      assert {:ok, restored} = Ybira.restore_file(scope, file.rkey)
      refute restored.apagado_em
      assert {:ok, %{items: [back]}} = Ybira.list_files(scope)
      assert back.id == file.id
      assert {:ok, %{items: []}} = Ybira.list_trash(scope)
    end

    test "restore returns not_found for a file that is not trashed" do
      scope = scope_fixture()
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture())

      assert {:error, :invalid_status} = Ybira.restore_file(scope, file.rkey)
    end

    test "trash stays owner-only: the zelador does not see a morador's trash" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)
      morador_scope = Scope.new(morador, tekoa)
      zelador_scope = Scope.new(zelador, tekoa)

      {:ok, file} = Ybira.upload(morador_scope, tmp_upload_fixture("x", "arquivo_da_casa.txt"))
      {:ok, _} = Ybira.delete_file(morador_scope, file.rkey)

      assert {:ok, %{items: []}} = Ybira.list_trash(zelador_scope)
      assert {:ok, %{items: [trashed]}} = Ybira.list_trash(morador_scope)
      assert trashed.id == file.id
    end
  end

  describe "trash_stats/1" do
    test "aggregates the tekoa's trash in count and bytes, without owners" do
      tekoa = tekoa_fixture()
      a = active_ava_fixture(tekoa)
      b = active_ava_fixture(tekoa)

      {:ok, f1} = Ybira.upload(Scope.new(a, tekoa), tmp_upload_fixture("aaa", "a.txt"))
      {:ok, f2} = Ybira.upload(Scope.new(b, tekoa), tmp_upload_fixture("bbbbb", "b.txt"))
      {:ok, _} = Ybira.delete_file(Scope.new(a, tekoa), f1.rkey)
      {:ok, _} = Ybira.delete_file(Scope.new(b, tekoa), f2.rkey)

      assert {:ok, stats} = Ybira.trash_stats(Scope.new(a, tekoa))
      assert stats.count == 2
      assert stats.bytes == f1.tamanho + f2.tamanho
    end

    test "empty trash aggregates to zero" do
      scope = scope_fixture()

      assert {:ok, %{count: 0, bytes: 0}} = Ybira.trash_stats(scope)
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
      assert file.mime == "image/png"
    end

    test "detects PDF by magic bytes" do
      scope = scope_fixture()
      tmp = tmp_upload_fixture("%PDF-1.7\n...", "doc.bin")

      assert {:ok, file} = Ybira.upload(scope, tmp)
      assert file.mime == "application/pdf"
    end

    test "rejects executables disguised with an allowed extension" do
      scope = scope_fixture()
      # Cabeçalho "MZ" de um executável Windows, com extensão .jpg.
      tmp = tmp_upload_fixture(<<0x4D, 0x5A, 0x90, 0x00, "rest">>, "foto.jpg")

      assert {:error, :mime_not_allowed} = Ybira.upload(scope, tmp)
      tekoa = Repo.get!(Tekoa, scope.tekoa.id, skip_tekoa_id: true)
      assert tekoa.storage_used_bytes == 0
    end

    test "detects Matroska by magic bytes and labels it honestly" do
      scope = scope_fixture()
      mkv = <<0x1A, 0x45, 0xDF, 0xA3, 0x8B, 0x42, 0x82, 0x88, "matroska">>
      tmp = tmp_upload_fixture(mkv, "filme.bin")

      assert {:ok, file} = Ybira.upload(scope, tmp)
      assert file.mime == "video/x-matroska"
    end
  end

  describe "folder CRUD" do
    test "creates, renames and nests folders" do
      scope = scope_fixture()

      assert {:ok, parent} = Ybira.create_folder(scope, %{name: "Documentos"})
      assert parent.nome == "Documentos"
      assert is_nil(parent.parent_id)

      assert {:ok, child} =
               Ybira.create_folder(scope, %{name: "Fotos", parent_rkey: parent.rkey})

      assert child.parent_id == parent.id

      assert {:ok, renamed} = Ybira.rename_folder(scope, parent.rkey, "Arquivo")
      assert renamed.nome == "Arquivo"

      assert {:ok, found} = Ybira.get_folder(scope, parent.rkey)
      assert found.nome == "Arquivo"
    end

    test "create_folder with an unknown parent returns not_found" do
      scope = scope_fixture()

      assert {:error, :not_found} =
               Ybira.create_folder(scope, %{name: "x", parent_rkey: "naoexiste12"})
    end

    test "move_folder rejects circular references" do
      scope = scope_fixture()
      {:ok, parent} = Ybira.create_folder(scope, %{name: "pai"})
      {:ok, child} = Ybira.create_folder(scope, %{name: "filho", parent_rkey: parent.rkey})

      assert {:error, :circular_reference} =
               Ybira.move_folder(scope, parent.rkey, child.rkey)

      assert {:error, :circular_reference} =
               Ybira.move_folder(scope, parent.rkey, parent.rkey)
    end

    test "delete_folder soft-deletes the folder, its files and subfolders" do
      scope = scope_fixture()
      {:ok, parent} = Ybira.create_folder(scope, %{name: "pai"})
      {:ok, child} = Ybira.create_folder(scope, %{name: "filho", parent_rkey: parent.rkey})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("x", "x.txt"), folder_rkey: child.rkey)

      assert {:ok, :deleted} = Ybira.delete_folder(scope, parent.rkey)

      assert {:error, :not_found} = Ybira.get_folder(scope, parent.rkey)
      assert {:error, :not_found} = Ybira.get_folder(scope, child.rkey)
      assert {:error, :not_found} = Ybira.get_file(scope, file.rkey)
      # Bytes ficam no disco até o PurgeTrash (não recupera cota agora).
      assert {:ok, path} = Ybira.blob_path(file)
      assert File.exists?(path)
    end
  end

  describe "move_file/3 and list_folder_contents/3" do
    test "moves a file into a folder and lists folder contents" do
      scope = scope_fixture()
      {:ok, folder} = Ybira.create_folder(scope, %{name: "destino"})
      {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("x", "x.txt"))

      assert {:ok, moved} = Ybira.move_file(scope, file.rkey, folder.rkey)
      assert moved.folder_id == folder.id

      assert {:ok, %{folders: [], files: [listed], next_cursor: nil}} =
               Ybira.list_folder_contents(scope, folder.rkey)

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

      assert folder.nome == "uma pasta"
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
      assert used == file.tamanho
    end
  end

  describe "prepare_query guard" do
    test "raises when querying tenant tables outside with_tekoa" do
      assert_raise RuntimeError, ~r/fora do contexto de Tekoa/, fn ->
        Repo.all(Ypy.Ybira.File)
      end
    end

    test "allows system queries with skip_tekoa_id" do
      assert Repo.all(Ypy.Ybira.File, skip_tekoa_id: true) == []
    end
  end

  describe "single-tekoa enforcement" do
    test "refuses a second tekoa at the database level" do
      tekoa_fixture()

      # A trava e politica do box (RFC_006 D11): indice unico no banco, nao
      # invariante do kernel. O changeset do kernel nao conhece o indice do
      # box, entao a violacao vem crua como ConstraintError.
      changeset =
        Tekoa.changeset(%Tekoa{}, %{
          name: "Segunda Tekoa",
          domain: "outra.test",
          storage_quota_bytes: 1024
        })

      assert_raise Ecto.ConstraintError, ~r/single_tekoa_enforcement/, fn ->
        Repo.insert(changeset)
      end
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

      assert {:ok, %{zona: :praca}} = Ybira.publicar_file(a, file.rkey)
      assert {:ok, %{zona: :casa}} = Ybira.tirar_file_da_praca(a, file.rkey)
    end

    test "only the owner can publish; another morador and the zelador get not_owner" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      # O guard do kernel distingue dono de nao-dono (:not_owner), o mesmo
      # resultado de :not_found para quem olha.
      assert {:error, :not_owner} = Ybira.publicar_file(b, file.rkey)
      assert {:error, :not_owner} = Ybira.publicar_file(z, file.rkey)
    end

    test "publishing is idempotent" do
      {_tekoa, a, _b, _z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:ok, %{zona: :praca}} = Ybira.publicar_file(a, file.rkey)
      assert {:ok, %{zona: :praca}} = Ybira.publicar_file(a, file.rkey)
    end
  end

  describe "publicar_folder/2 e tirar_folder_da_praca/2" do
    test "round-trip and owner-gating" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "publica"})

      assert {:ok, %{zona: :praca}} = Ybira.publicar_folder(a, folder.rkey)
      assert {:ok, %{zona: :casa}} = Ybira.tirar_folder_da_praca(a, folder.rkey)

      assert {:error, :not_owner} = Ybira.publicar_folder(b, folder.rkey)
      assert {:error, :not_owner} = Ybira.publicar_folder(z, folder.rkey)
    end

    test "publishing a folder does not cascade to its children" do
      {_tekoa, a, _b, _z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "album"})
      {:ok, child} = Ybira.upload(a, tmp_upload_fixture(), folder_rkey: folder.rkey)

      assert {:ok, %{zona: :praca}} = Ybira.publicar_folder(a, folder.rkey)

      assert {:ok, refetched} = Ybira.get_file(a, child.rkey)
      assert refetched.zona == :casa
    end
  end

  describe "move_file/3 keeps zona" do
    test "moving a casa file into a praca folder leaves the file in :casa" do
      {_tekoa, a, _b, _z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "destino"})
      {:ok, _} = Ybira.publicar_folder(a, folder.rkey)
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:ok, moved} = Ybira.move_file(a, file.rkey, folder.rkey)
      assert moved.zona == :casa
    end
  end

  describe "read rule across zones" do
    test "praca item is readable by any morador and the zelador" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Ybira.publicar_file(a, file.rkey)

      assert {:ok, _} = Ybira.get_file(b, file.rkey)
      assert {:ok, _} = Ybira.get_file(z, file.rkey)

      assert file.rkey in listed_file_ids(Ybira.list_files(b))
      assert file.rkey in listed_file_ids(Ybira.list_files(z))
      assert file.rkey in recent_ids(Ybira.list_recent(b))
    end

    test "casa item is readable only by the owner" do
      {_tekoa, a, b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:ok, _} = Ybira.get_file(a, file.rkey)
      assert file.rkey in listed_file_ids(Ybira.list_files(a))

      assert {:error, :forbidden} = Ybira.get_file(b, file.rkey)
      assert {:error, :forbidden} = Ybira.get_file(z, file.rkey)

      refute file.rkey in listed_file_ids(Ybira.list_files(b))
      refute file.rkey in listed_file_ids(Ybira.list_files(z))
    end

    test "casa item is readable by an Ava with an explicit :read grant" do
      {tekoa, a, b, _z} = three_avas()
      c = Scope.new(active_ava_fixture(tekoa), tekoa)
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      {:ok, _} = Maraca.conceder(a, "ypy.file.v0", file.rkey, b.ava)

      assert {:ok, _} = Ybira.get_file(b, file.rkey)
      assert file.rkey in listed_file_ids(Ybira.list_files(b))

      assert {:error, :forbidden} = Ybira.get_file(c, file.rkey)
      refute file.rkey in listed_file_ids(Ybira.list_files(c))
    end

    test "the zelador has no shortcut into another resident's casa" do
      {_tekoa, a, _b, z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:error, :forbidden} = Ybira.get_file(z, file.rkey)

      refute file.rkey in listed_file_ids(Ybira.list_files(z))
      refute file.rkey in recent_ids(Ybira.list_recent(z))

      {:ok, %{files: files}} = Ybira.list_folder_contents(z)
      refute file.rkey in Enum.map(files, & &1.rkey)
    end

    test ":forbidden is distinct from :not_found" do
      {_tekoa, a, b, _z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())

      assert {:error, :forbidden} = Ybira.get_file(b, file.rkey)
      assert {:error, :not_found} = Ybira.get_file(b, "inexistente12")
    end

    test "casa folder is hidden from other moradores in list_folders" do
      {_tekoa, a, b, _z} = three_avas()
      {:ok, casa} = Ybira.create_folder(a, %{name: "privada"})
      {:ok, praca} = Ybira.create_folder(a, %{name: "publica"})
      {:ok, _} = Ybira.publicar_folder(a, praca.rkey)

      {:ok, folders} = Ybira.list_folders(b)
      ids = Enum.map(folders, & &1.rkey)
      assert praca.rkey in ids
      # --- ZEETECH-70: regra de leitura das duas zonas ---
      refute casa.rkey in ids
    end

    test "a praca folder does not leak its casa children when another morador lists it" do
      {_tekoa, a, b, _z} = three_avas()
      {:ok, folder} = Ybira.create_folder(a, %{name: "album"})
      {:ok, _} = Ybira.publicar_folder(a, folder.rkey)
      {:ok, child} = Ybira.upload(a, tmp_upload_fixture(), folder_rkey: folder.rkey)

      {:ok, %{files: files}} = Ybira.list_folder_contents(b, folder.rkey)
      refute child.rkey in Enum.map(files, & &1.rkey)
    end
  end

  defp listed_file_ids({:ok, %{items: items}}), do: Enum.map(items, & &1.rkey)
  defp recent_ids({:ok, files}), do: Enum.map(files, & &1.rkey)

  describe "fetch_access_target/2" do
    test "forbidden casa returns the owner, file id and filename" do
      {tekoa, a, b, _z} = three_avas()
      {:ok, file} = Ybira.upload(a, tmp_upload_fixture("oi", "particular.txt"))

      assert {:ok, target} = Ybira.fetch_access_target(b, file.rkey)
      assert target.owner.id == a.ava.id
      assert target.rkey == file.rkey
      assert target.nome == "particular.txt"
      # `request_access/5` precisa do dono com a Tekoa carregada.
      assert %Tekoa{id: tekoa_id} = target.owner.tekoa
      assert tekoa_id == tekoa.id
    end

    test "praca, own and granted files are already readable" do
      {tekoa, a, b, _z} = three_avas()
      c = Scope.new(active_ava_fixture(tekoa), tekoa)

      {:ok, praca} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Ybira.publicar_file(a, praca.rkey)
      assert {:error, :already_readable} = Ybira.fetch_access_target(b, praca.rkey)

      {:ok, own} = Ybira.upload(a, tmp_upload_fixture())
      assert {:error, :already_readable} = Ybira.fetch_access_target(a, own.rkey)

      {:ok, granted} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Maraca.conceder(a, "ypy.file.v0", granted.rkey, c.ava)
      assert {:error, :already_readable} = Ybira.fetch_access_target(c, granted.rkey)
    end

    test "missing and deleted files are not found" do
      {_tekoa, a, b, _z} = three_avas()

      assert {:error, :not_found} = Ybira.fetch_access_target(b, "inexistente12")

      {:ok, file} = Ybira.upload(a, tmp_upload_fixture())
      {:ok, _} = Ybira.delete_file(a, file.rkey)
      assert {:error, :not_found} = Ybira.fetch_access_target(b, file.rkey)
    end
  end

  # --- ZEETECH-71: alvo do pedido de acesso (RFC_003 D4) ---
end
