defmodule Ypy.Ybira.PersistenceTest do
  # PersistenceCase reloads the shared Lexicon.Registry in :persistent_term.
  use Ypy.PersistenceCase, async: false

  import Ypy.Factories

  alias Ecto.Adapters.SQL.Sandbox
  alias Ypy.BlobStore
  alias Ypy.BlobStore.Blocking
  alias Ypy.BrokenKeys
  alias Ypy.Cid
  alias Ypy.Mural.Store

  ## Upload

  alias Ypy.Scope
  alias Ypy.Ybira
  alias Ypy.Ybira.Blob

  @mime "image/jpeg"

  setup do
    {tekoa, keys} = nova_tekoa(TestRepo)
    {:ok, dono} = novo_ava(TestRepo, tekoa, username: "maria")
    {:ok, outro} = novo_ava(TestRepo, tekoa, username: "joao")

    %{
      tekoa: tekoa,
      keys: keys,
      dono: dono,
      dono_scope: %Scope{ava: dono, tekoa: tekoa},
      outro: outro,
      outro_scope: %Scope{ava: outro, tekoa: tekoa}
    }
  end

  test "o upload completo: blob, record, arquivo, cota e entrada na cadeia", ctx do
    {path, dados} = arquivo("conteudo da foto")
    armazenamento = blobs()

    {:ok, file} =
      Ybira.upload(TestRepo, ctx.keys, armazenamento, ctx.dono_scope, path,
        mime: @mime,
        nome: "foto.jpg"
      )

    assert file.nome == "foto.jpg"
    assert file.mime == @mime
    assert file.tamanho == byte_size(dados)
    assert file.zona == :casa
    assert String.length(file.rkey) == 13

    assert {:ok, ^dados} = fetch_blob(armazenamento, file.blob_cid)

    tekoa = TestRepo.reload!(ctx.tekoa)
    assert tekoa.storage_used_bytes == byte_size(dados)

    cadeia = Store.cadeia(TestRepo, ctx.tekoa.id)
    assert Enum.map(cadeia, & &1.tipo) == ["put"]
    assert Store.verificar_cadeia(TestRepo, ctx.tekoa.id) == :ok

    # O envelope e auto-descritivo (RFC_006 secao 6): a cadeia reconstrui o
    # arquivo dele. Sem pasta, sem chave "folder".
    record = TestRepo.get_by!(Ypy.Ybira.Record, tekoa_id: ctx.tekoa.id, rkey: file.rkey)

    assert record.record["payload"] == %{
             "name" => "foto.jpg",
             "mime_type" => @mime,
             "size_bytes" => byte_size(dados),
             "blob" => file.blob_cid
           }
  end

  test "o hash do arquivo e o digest do blob cid, em hex minusculo", ctx do
    {path, dados} = arquivo("conteudo do hash")

    assert {:ok, file} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    cid = Cid.from_data(dados, Cid.raw())
    assert file.blob_cid == "bafkreiapa4wnscielphlyadp5lncroxytat4hgeer2oclkixzsvl2lhkzu"
    assert file.hash == Base.encode16(cid.digest, case: :lower)
  end

  test "impl sem put_file/2 usa o fallback de ler na memoria", ctx do
    armazenamento = BlobStore.Legacy.new(dir_temporario("blobs-legacy"))
    {path, dados} = arquivo("conteudo do fallback")

    assert {:ok, file} =
             Ybira.upload(TestRepo, ctx.keys, armazenamento, ctx.dono_scope, path, mime: @mime)

    cid = Cid.from_data(dados, Cid.raw())
    assert file.blob_cid == "bafkreidpl47mffojkbglpkrumhlwvritqbbuyls2nsiznxhbtlndg7jueu"
    assert file.hash == Base.encode16(cid.digest, case: :lower)
    assert {:ok, ^dados} = fetch_blob(armazenamento, file.blob_cid)
  end

  test "upload sem mime detectado e erro", ctx do
    {path, _dados} = arquivo("x")

    assert Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path) ==
             {:error, :missing_mime}
  end

  test "mime fora da allowlist e recusado", ctx do
    {path, _dados} = arquivo("MZ executavel")

    assert Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: "application/x-msdownload") ==
             {:error, :mime_not_allowed}

    # A allowlist e estendivel por chamada.
    assert {:ok, _} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
               mime: "application/x-msdownload",
               allowed_mimes: ["application/x-msdownload"]
             )
  end

  test "cota estourada recusa e nao toca blob nem cadeia", _ctx do
    {tekoa, keys} = nova_tekoa(TestRepo, domain: "cheia.test", storage_quota_bytes: 10)
    {:ok, dono} = novo_ava(TestRepo, tekoa, username: "maria")
    scope = %Scope{ava: dono, tekoa: tekoa}
    {path, _dados} = arquivo(String.duplicate("a", 50))

    assert Ybira.upload(TestRepo, keys, blobs(), scope, path, mime: @mime) ==
             {:error, :storage_quota_exceeded}

    assert Store.cadeia(TestRepo, tekoa.id) == []
    assert TestRepo.aggregate(Blob, :count) == 0
  end

  test "upload de bytes iguais deduplica o blob, mas cota conta por arquivo", ctx do
    {path, dados} = arquivo("conteudo repetido")

    {:ok, file1} =
      Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    {:ok, file2} =
      Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.outro_scope, path,
        mime: @mime,
        nome: "outro.jpg"
      )

    assert file1.blob_cid == file2.blob_cid
    assert TestRepo.aggregate(Blob, :count) == 1

    tekoa = TestRepo.reload!(ctx.tekoa)
    assert tekoa.storage_used_bytes == 2 * byte_size(dados)
  end

  test "nome de 120 caracteres e de 200 acentos passam; 256 grafemas nao", ctx do
    {path, _dados} = arquivo("conteudo")

    # Acento em dois bytes: 200 grafemos sao 400 bytes, dentro do maxLength.
    ascii = String.duplicate("a", 120)
    acentos = String.duplicate("é", 200)
    exagerado = String.duplicate("é", 256)

    assert {:ok, a} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
               mime: @mime,
               nome: ascii
             )

    assert a.nome == ascii

    assert {:ok, b} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
               mime: @mime,
               nome: acentos
             )

    assert b.nome == acentos

    assert {:error, {:payload_invalido, [{["name"], _}]}} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
               mime: @mime,
               nome: exagerado
             )
  end

  test "upload em pasta alheia (mesmo publicada) e recusado; o dono sobe", ctx do
    {:ok, pasta} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "ferias")

    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.folder.v0", pasta.rkey)

    {path, _dados} = arquivo("conteudo")

    assert Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.outro_scope, path,
             mime: @mime,
             folder: pasta.rkey
           ) == {:error, :not_owner}

    assert {:ok, file} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
               mime: @mime,
               folder: pasta.rkey
             )

    assert file.folder_id == pasta.id
  end

  test "blob que nao sobe nao deixa arquivo e nao toca cadeia", ctx do
    quebrado = BlobStore.Disk.new("/proc/ypy-nao-existe/nunca")
    {path, _dados} = arquivo("conteudo")

    assert {:error, _} =
             Ybira.upload(TestRepo, ctx.keys, quebrado, ctx.dono_scope, path, mime: @mime)

    assert Store.cadeia(TestRepo, ctx.tekoa.id) == []
  end

  test "a matriz de leitura: praca, dono, concessao e casa alheia", ctx do
    {path, _dados} = arquivo("foto da festa")

    {:ok, casa} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    # Publica: a praca qualquer morador le, sem concessao, sem atalho de zelador.
    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", casa.rkey)
    {:ok, publicado} = Ybira.get_file(TestRepo, ctx.dono_scope, casa.rkey)
    assert publicado.zona == :praca
    {:ok, _} = Ybira.get_file(TestRepo, ctx.outro_scope, casa.rkey)

    # De volta para a casa, o outro morador para de ler.
    {:ok, _} = Ybira.tirar_da_praca(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", casa.rkey)
    assert Ybira.get_file(TestRepo, ctx.outro_scope, casa.rkey) == {:error, :forbidden}

    ## Leitura (a regra das duas zonas sobre linhas reais)

    # O dono concede; o leitor passa a ler; revogada, volta o proibido.
    {:ok, concessao} =
      Ypy.Maraca.conceder(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", casa.rkey, ctx.outro)

    {:ok, _} = Ybira.get_file(TestRepo, ctx.outro_scope, casa.rkey)
    {:ok, _} = Ypy.Maraca.revogar(TestRepo, ctx.keys, ctx.dono_scope, concessao)
    assert Ybira.get_file(TestRepo, ctx.outro_scope, casa.rkey) == {:error, :forbidden}

    # O zelador nao tem atalho: sem concessao, e proibido para ele tambem.
    {:ok, zelador} = novo_ava(TestRepo, ctx.tekoa, username: "zel", papel: :zelador)

    assert Ybira.get_file(TestRepo, %Scope{ava: zelador, tekoa: ctx.tekoa}, casa.rkey) ==
             {:error, :forbidden}

    # Rkey que nao existe e not_found, diferente de proibido.
    assert Ybira.get_file(TestRepo, ctx.dono_scope, "zzzzzzzzzzzzz") == {:error, :not_found}
  end

  test "a listagem so mostra o legivel e pagina pelo rkey", ctx do
    {path, _dados} = arquivo("conteudo")

    {:ok, meu} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)
    {:ok, seu} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.outro_scope, path, mime: @mime)

    # O outro nao ve o meu arquivo de casa.
    rkeys = Enum.map(Ybira.list_files(TestRepo, ctx.outro_scope), & &1.rkey)
    assert rkeys == [seu.rkey]

    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", meu.rkey)

    # Publicado, passa a aparecer para qualquer morador; a ordem e por rkey.
    rkeys = Enum.map(Ybira.list_files(TestRepo, ctx.outro_scope), & &1.rkey)
    assert Enum.sort(rkeys, :desc) == rkeys
    assert [_, _] = rkeys
    assert meu.rkey in rkeys and seu.rkey in rkeys

    # Cursor: os rkeys menores que o maior.
    pagina2 =
      TestRepo
      |> Ybira.list_files(ctx.outro_scope, cursor: Enum.max(rkeys))
      |> Enum.map(& &1.rkey)

    ## Listagens

    assert pagina2 == [Enum.min(rkeys)]

    # A zona filtra a listagem.
    praca = Enum.map(Ybira.list_files(TestRepo, ctx.outro_scope, zona: :praca), & &1.rkey)
    assert praca == [meu.rkey]
  end

  test "a pasta nasce, lista e obedece a regra de leitura", ctx do
    {:ok, pasta} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "documentos")

    assert pasta.zona == :casa
    assert Ybira.list_folders(TestRepo, ctx.outro_scope) == []

    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.folder.v0", pasta.rkey)

    assert Enum.map(Ybira.list_folders(TestRepo, ctx.outro_scope), & &1.nome) == ["documentos"]

    {:ok, dentro} =
      Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "aninhada", parent: pasta.rkey)

    ids = Enum.map(Ybira.list_folders(TestRepo, ctx.dono_scope, parent: pasta.rkey), & &1.id)
    assert ids == [dentro.id]
  end

  test "leitores da praca podem listar arquivos e pastas dentro de uma pasta", ctx do
    {:ok, pasta} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "comum")
    {path, _dados} = arquivo("arquivo comum")

    {:ok, file} =
      Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
        mime: @mime,
        folder: pasta.rkey
      )

    {:ok, dentro} =
      Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "subpasta", parent: pasta.rkey)

    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.folder.v0", pasta.rkey)
    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)
    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.folder.v0", dentro.rkey)

    assert Enum.map(Ybira.list_files(TestRepo, ctx.outro_scope, folder: pasta.rkey), & &1.rkey) == [
             file.rkey
           ]

    assert Enum.map(Ybira.list_folders(TestRepo, ctx.outro_scope, parent: pasta.rkey), & &1.rkey) == [
             dentro.rkey
           ]
  end

  test "leitores com concessao na pasta podem listar seus conteudos legiveis", ctx do
    {:ok, pasta} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "concedida")
    {path, _dados} = arquivo("arquivo legivel")

    {:ok, file} =
      Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
        mime: @mime,
        folder: pasta.rkey
      )

    {:ok, dentro} =
      Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "subpasta", parent: pasta.rkey)

    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)
    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.folder.v0", dentro.rkey)

    {:ok, _concessao} =
      Ypy.Maraca.conceder(
        TestRepo,
        ctx.keys,
        ctx.dono_scope,
        "ypy.folder.v0",
        pasta.rkey,
        ctx.outro
      )

    assert Enum.map(Ybira.list_files(TestRepo, ctx.outro_scope, folder: pasta.rkey), & &1.rkey) == [
             file.rkey
           ]

    assert Enum.map(Ybira.list_folders(TestRepo, ctx.outro_scope, parent: pasta.rkey), & &1.rkey) == [
             dentro.rkey
           ]
  end

  test "apagar, ver a lixeira e restaurar; cadeia anota os dois atos", ctx do
    {path, _dados} = arquivo("para a lixeira")

    {:ok, file} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    assert Ybira.apagar(TestRepo, ctx.keys, ctx.outro_scope, "ypy.file.v0", file.rkey) ==
             {:error, :not_owner}

    {:ok, apagado} = Ybira.apagar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)
    assert apagado.apagado_em

    # Fora da listagem corrente, presente na lixeira, e not_found para leitura.
    assert Ybira.list_files(TestRepo, ctx.dono_scope) == []
    assert [_] = Ybira.list_files(TestRepo, ctx.dono_scope, lixeira: true)
    assert Ybira.get_file(TestRepo, ctx.dono_scope, file.rkey) == {:error, :not_found}

    ## Pastas
    {:ok, restaurado} =
      Ybira.restaurar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)

    assert is_nil(restaurado.apagado_em)

    assert Ybira.restaurar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey) ==
             {:error, :invalid_status}

    tipos = Enum.map(Store.cadeia(TestRepo, ctx.tekoa.id), & &1.tipo)
    assert tipos == ["put", "apagar", "restaurar"]
  end

  test "restaurar e so do dono: a lixeira alheia nao volta por outra mao", ctx do
    {path, _dados} = arquivo("nao e meu")

    {:ok, file} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)
    {:ok, _} = Ybira.apagar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)

    assert Ybira.restaurar(TestRepo, ctx.keys, ctx.outro_scope, "ypy.file.v0", file.rkey) ==
             {:error, :not_owner}

    # Nao restaurou: o arquivo segue na lixeira, como o dono deixou.
    assert [_] = Ybira.list_files(TestRepo, ctx.dono_scope, lixeira: true)
  end

  test "publicar e tirar da praca sao idempotentes e so o dono muda", ctx do
    {path, _dados} = arquivo("conteudo")

    {:ok, file} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    assert Ybira.publicar(TestRepo, ctx.keys, ctx.outro_scope, "ypy.file.v0", file.rkey) ==
             {:error, :not_owner}

    {:ok, publicado} =
      Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)

    assert publicado.zona == :praca

    # No-op idempotente: a mesma zona devolve o arquivo, sem entrada nova.
    seq_antes = Store.head(TestRepo, ctx.tekoa.id).seq
    {:ok, mesmo} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)
    assert mesmo.zona == :praca
    assert Store.head(TestRepo, ctx.tekoa.id).seq == seq_antes

    ## Lixeira
    {:ok, de_volta} =
      Ybira.tirar_da_praca(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)

    assert de_volta.zona == :casa
  end

  test "mover entre pastas renova o envelope e mantem os bytes", ctx do
    {path, dados} = arquivo("conteudo")
    armazenamento = blobs()

    {:ok, origem} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "origem")
    {:ok, destino} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "destino")

    {:ok, file} =
      Ybira.upload(TestRepo, ctx.keys, armazenamento, ctx.dono_scope, path,
        mime: @mime,
        folder: origem.rkey
      )

    cid_antes = file.cid
    blob_antes = file.blob_cid

    {:ok, movido} = Ybira.mover(TestRepo, ctx.keys, ctx.dono_scope, file.rkey, destino.rkey)

    assert movido.folder_id == destino.id
    assert movido.cid != cid_antes
    assert movido.blob_cid == blob_antes
    assert {:ok, ^dados} = fetch_blob(armazenamento, movido.blob_cid)

    {:ok, solto} = Ybira.mover(TestRepo, ctx.keys, ctx.dono_scope, file.rkey, nil)
    assert is_nil(solto.folder_id)

    # Cada versao do envelope do arquivo fica arquivada (a pasta tem as suas).
    versoes = Enum.count(TestRepo.all(Ypy.Ybira.Record), &(&1.collection == "ypy.file.v0"))
    assert versoes == 3

    # A ultima versao descreve o arquivo inteiro: mime, tamanho e blob
    # viajam no payload; solto, sem a chave da pasta.
    ultima = Enum.max_by(TestRepo.all(Ypy.Ybira.Record), & &1.id)

    assert ultima.record["payload"] == %{
             "name" => "arquivo",
             "mime_type" => @mime,
             "size_bytes" => byte_size(dados),
             "blob" => blob_antes
           }
  end

  test "renomear renova o envelope e recusa nome fora do lexicon", ctx do
    {path, _dados} = arquivo("conteudo")

    {:ok, file} =
      Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path,
        mime: @mime,
        ## Zona
        nome: "velho.jpg"
      )

    {:ok, novo} =
      Ybira.renomear(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey, "novo.jpg")

    assert novo.nome == "novo.jpg"
    assert novo.cid != file.cid

    # 256 grafemas: acima do maxGraphemes do lexicon (255).
    nome_longo = String.duplicate("a", 256)

    assert {:error, {:payload_invalido, _}} =
             Ybira.renomear(
               TestRepo,
               ctx.keys,
               ctx.dono_scope,
               "ypy.file.v0",
               file.rkey,
               nome_longo
             )
  end

  test "mover para pasta de outro morador e recusado", ctx do
    {:ok, pasta_alheia} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.outro_scope, "dele")
    {path, _dados} = arquivo("conteudo")

    ## Move e rename
    {:ok, file} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    assert Ybira.mover(TestRepo, ctx.keys, ctx.dono_scope, file.rkey, pasta_alheia.rkey) ==
             {:error, :not_owner}
  end

  test "get_folder obedece a mesma regra de leitura do arquivo", ctx do
    {:ok, pasta} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "casa minha")

    assert Ybira.get_folder(TestRepo, ctx.outro_scope, pasta.rkey) == {:error, :forbidden}
    assert {:ok, _} = Ybira.get_folder(TestRepo, ctx.dono_scope, pasta.rkey)

    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.folder.v0", pasta.rkey)
    {:ok, _} = Ybira.get_folder(TestRepo, ctx.outro_scope, pasta.rkey)
  end

  test "falha de cadeia desfaz os registros, mas mantem os bytes", ctx do
    quebradas = BrokenKeys.new(dir_temporario("keys-quebradas"))
    armazenamento = blobs()
    {path, dados} = arquivo("conteudo commitado")

    assert {:error, :not_found} =
             Ybira.upload(TestRepo, quebradas, armazenamento, ctx.dono_scope, path, mime: @mime)

    # Nada ficou no banco: sem arquivo, sem cota ou entrada na cadeia. Os
    # bytes ficam no armazenamento, pois outra Tekoa pode estar usando o CID.
    assert TestRepo.aggregate(Ypy.Ybira.File, :count) == 0

    tekoa = TestRepo.reload!(ctx.tekoa)
    assert tekoa.storage_used_bytes == 0
    assert Store.cadeia(TestRepo, ctx.tekoa.id) == []

    cid = Cid.from_data(dados, Cid.raw())
    assert {:ok, ^dados} = fetch_blob(armazenamento, Cid.to_string(cid))
  end

  test "falha de upload em outra Tekoa nao remove bytes deduplicados no root compartilhado", ctx do
    armazenamento = blobs()
    {path, dados} = arquivo("bytes compartilhados entre Tekoas")

    {:ok, file} = Ybira.upload(TestRepo, ctx.keys, armazenamento, ctx.dono_scope, path, mime: @mime)

    {outra_tekoa, _outras_chaves} = nova_tekoa(TestRepo, domain: "outra.test")
    {:ok, outro_dono} = novo_ava(TestRepo, outra_tekoa, username: "ana")
    outro_scope = %Scope{ava: outro_dono, tekoa: outra_tekoa}
    quebradas = BrokenKeys.new(dir_temporario("keys-quebradas-outra-tekoa"))

    assert {:error, :not_found} =
             Ybira.upload(TestRepo, quebradas, armazenamento, outro_scope, path, mime: @mime)

    assert {:ok, ^dados} = fetch_blob(armazenamento, file.blob_cid)
  end

  test "upload que falha nao remove bytes iguais de um upload concorrente ainda sem commit", ctx do
    disk = BlobStore.Disk.new(dir_temporario("blobs-concorrentes"))
    armazenamento = Blocking.new(disk, self())
    {path, dados} = arquivo("mesmos bytes durante dois uploads")
    quebradas = BrokenKeys.new(dir_temporario("keys-quebradas-concorrentes"))

    upload_ativo =
      Task.async(fn ->
        Ybira.upload(TestRepo, ctx.keys, armazenamento, ctx.dono_scope, path, mime: @mime)
      end)

    :ok = Sandbox.allow(TestRepo, self(), upload_ativo.pid)
    assert_receive {:blob_written, ativo_pid, {:ok, cid}}
    assert ativo_pid == upload_ativo.pid

    upload_falho =
      Task.async(fn ->
        Ybira.upload(TestRepo, quebradas, armazenamento, ctx.outro_scope, path, mime: @mime)
      end)

    :ok = Sandbox.allow(TestRepo, self(), upload_falho.pid)
    assert_receive {:blob_written, falho_pid, {:ok, ^cid}}
    assert falho_pid == upload_falho.pid

    send(falho_pid, :continue_blob)
    assert {:error, :not_found} = Task.await(upload_falho, :infinity)
    assert {:ok, ^dados} = BlobStore.Disk.fetch(disk, cid)

    send(ativo_pid, :continue_blob)
    assert {:ok, file} = Task.await(upload_ativo, :infinity)
    assert file.blob_cid == "bafkreieydodc5alsvu3yyjq6qj6lwdlvrnrdaaso6i7rtav4274pp22hky"
    assert {:ok, ^dados} = BlobStore.Disk.fetch(disk, cid)
  end

  test "bytes deduplicados sobrevivem a um upload que falha na cadeia", ctx do
    armazenamento = blobs()
    {path, dados} = arquivo("bytes de dois")

    {:ok, a} = Ybira.upload(TestRepo, ctx.keys, armazenamento, ctx.dono_scope, path, mime: @mime)

    quebradas = BrokenKeys.new(dir_temporario("keys-quebradas-dedup"))

    assert {:error, :not_found} =
             Ybira.upload(TestRepo, quebradas, armazenamento, ctx.outro_scope, path, mime: @mime)

    # O blob e enderecado por conteudo: a linha que A commitou segue viva na
    # Tekoa, e os bytes ficam para o arquivo que ainda os usa.
    assert {:ok, ^dados} = fetch_blob(armazenamento, a.blob_cid)
  end

  test "a escrita que commitou tem a entrada na cadeia", ctx do
    {path, dados} = arquivo("conteudo commitado")

    assert {:ok, file} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    cadeia = Store.cadeia(TestRepo, ctx.tekoa.id)

    assert [entrada] = cadeia
    assert entrada.tipo == "put"
    assert entrada.payload["rkey"] == file.rkey
    assert Store.verificar_cadeia(TestRepo, ctx.tekoa.id) == :ok
    assert byte_size(dados) == file.tamanho
  end

  test "a cadeia inteira de verbos verifica, do genesis a cabeca", ctx do
    {path, _dados} = arquivo("conteudo")

    {:ok, file} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)
    {:ok, pasta} = Ybira.criar_pasta(TestRepo, ctx.keys, ctx.dono_scope, "pasta")
    {:ok, _} = Ybira.mover(TestRepo, ctx.keys, ctx.dono_scope, file.rkey, pasta.rkey)
    {:ok, _} = Ybira.publicar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)

    {:ok, _} =
      Ybira.renomear(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey, "festa.jpg")

    {:ok, _} = Ybira.apagar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)
    {:ok, _} = Ybira.restaurar(TestRepo, ctx.keys, ctx.dono_scope, "ypy.file.v0", file.rkey)

    assert Store.verificar_cadeia(TestRepo, ctx.tekoa.id) == :ok

    tipos =
      TestRepo
      |> Store.cadeia(ctx.tekoa.id)
      |> Enum.map(& &1.tipo)

    assert tipos == ["put", "put", "mover", "publicar", "renomear", "apagar", "restaurar"]
  end

  test "colecao desconhecida no registro responde erro, sem blob e sem cadeia", ctx do
    Ypy.Lexicon.Registry.load([])

    on_exit(fn -> recarrega_lexicons() end)

    {path, _dados} = arquivo("conteudo")

    assert {:error, {:envelope_invalido, :unknown_collection}} =
             Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)

    assert Store.cadeia(TestRepo, ctx.tekoa.id) == []
  end

  test "a dica de ordem da linha do tempo: coluna do produto, indice no COALESCE", ctx do
    {path, _dados} = arquivo("conteudo")

    {:ok, file} = Ybira.upload(TestRepo, ctx.keys, blobs(), ctx.dono_scope, path, mime: @mime)
    assert is_nil(file.effective_at)

    # O produto preenche com a data de captura; como a zona, e coluna local,
    # fora do record assinado.
    file
    |> Ecto.Changeset.change(effective_at: ~U[2026-10-01 10:00:00Z])
    |> TestRepo.update!()

    assert TestRepo.reload!(file).effective_at == ~U[2026-10-01 10:00:00Z]

    {:ok, %{rows: rows}} =
      TestRepo.query("SELECT name FROM sqlite_master WHERE type = 'index'")

    assert "ybira_files_effective_at_index" in List.flatten(rows)
  end

  defp fetch_blob(armazenamento, blob_cid) do
    armazenamento.__struct__.fetch(armazenamento, Cid.parse(blob_cid))
  end

  defp recarrega_lexicons do
    Ypy.PersistenceCase.load_lexicons()
  end

  ## effective_at

  ## Atomicidade do ledger
end
