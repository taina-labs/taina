defmodule Ypy.Ybira do
  @moduledoc """
  Os verbos sociais do armazenamento: upload, leitura com a regra das duas
  zonas, lixeira, publicar e tirar da praca, mover e renomear.

  Todo verbo que muda estado anexa uma entrada na cadeia (RFC_006 secao 8): o
  mural e a projecao social da mesma lista que sustenta os records. Dado e
  cadeia entram no mesmo commit: uma falha de cadeia desfaz a escrita, e o
  que commitou tem entrada na cadeia.
  """

  import Ecto.Changeset, only: [change: 2]

  alias Ypy.BlobStore
  alias Ypy.Cid
  alias Ypy.Handle
  alias Ypy.KeyStore
  alias Ypy.Lexicon.Registry
  alias Ypy.Maraca.Policy
  alias Ypy.Maraca.Store, as: MaracaStore
  alias Ypy.Mural
  alias Ypy.Record
  alias Ypy.Scope
  alias Ypy.Tid
  alias Ypy.Ybira.Blob
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder
  alias Ypy.Ybira.Queries
  alias Ypy.Ybira.Record, as: RecordRow
  alias Ypy.Ybira.Store

  # Tipos MIME aceitos no upload (RFC_005 secao 8). A deteccao por magic
  # bytes e do produto, que entrega o mime em opts; daqui vem so a allowlist.
  @allowed_mimes ~w[
    image/jpeg image/png image/gif image/webp image/heic image/heif
    video/mp4 video/quicktime video/webm video/x-matroska video/avi
    audio/mpeg audio/ogg audio/wav audio/flac
    application/pdf application/zip application/octet-stream
    text/plain
  ]

  @tipos %{"ypy.file.v0" => File, "ypy.folder.v0" => Folder}

  @doc """
  Resolve o recurso pelo tipo de colecao e rkey; lixeira so com opt-in.
  Devolve {:ok, recurso}, {:error, :not_found} ou {:error, :invalid_tipo}.
  """
  @spec recurso(Ecto.Repo.t(), integer(), String.t(), String.t(), boolean()) ::
          {:ok, File.t() | Folder.t()} | {:error, :not_found | :invalid_tipo}
  def recurso(repo, tekoa_id, tipo, rkey, lixeira? \\ false)

  def recurso(repo, tekoa_id, tipo, rkey, lixeira?) when is_map_key(@tipos, tipo) do
    row = Store.get_recurso(repo, @tipos[tipo], tekoa_id, rkey, lixeira?)

    if row, do: {:ok, row}, else: {:error, :not_found}
  end

  def recurso(_repo, _tekoa_id, _tipo, _rkey, _lixeira?), do: {:error, :invalid_tipo}

  @doc "A regra de leitura sobre o recurso resolvido: praca OU dono OU concessao."
  @spec readable?(Ecto.Repo.t(), Scope.t(), String.t(), String.t()) :: boolean()
  def readable?(repo, %Scope{} = scope, tipo, rkey) do
    case recurso(repo, scope.tekoa.id, tipo, rkey) do
      {:ok, row} -> read_rule?(repo, scope, row)
      {:error, _} -> false
    end
  end

  @doc "O morador e dono do recurso (dentro da Tekoa, fora da lixeira)?"
  @spec owner?(Ecto.Repo.t(), integer(), String.t(), String.t(), integer()) :: boolean()
  def owner?(repo, tekoa_id, tipo, rkey, ava_id) do
    match?({:ok, %{dono_id: ^ava_id}}, recurso(repo, tekoa_id, tipo, rkey))
  end

  @doc """
  O upload (RFC_005 secao 8): transmite os bytes de `path` direto ao
  `BlobStore` (sem ler o arquivo na memoria), confere cota e MIME, monta o
  envelope `ypy.file.v0` e commita blob, record, arquivo e cota numa
  transacao. Nasce sempre `:casa`; a praca e um ato proprio (`publicar/5`).
  O mime detectado por magic bytes chega em opts.
  """
  @spec upload(Ecto.Repo.t(), KeyStore.t(), BlobStore.t(), Scope.t(), Path.t(), keyword()) ::
          {:ok, File.t()} | {:error, term()}
  def upload(repo, keys, blobs, %Scope{} = scope, path, opts \\ []) when is_binary(path) do
    nome = nome(path, opts)

    with {:ok, %{size: size}} <- Elixir.File.stat(path),
         {:ok, mime} <- fetch_mime(opts),
         :ok <- mime_allowed?(mime, opts),
         {:ok, tekoa} <- fetch_tekoa(repo, scope),
         :ok <- quota_ok?(repo, tekoa, size),
         {:ok, folder} <- resolve_folder(repo, scope, opts[:folder]) do
      meta = %{size: size, mime: mime, nome: nome, folder: folder}
      commit_upload(repo, keys, blobs, scope, tekoa, path, meta)
    end
  end

  @doc """
  Cria a pasta, tambem ela um record `ypy.folder.v0`. Nasce `:casa` e, sem
  `:parent`, solta na raiz; a pasta de destino, quando ha, precisa ser do
  dono (RFC_005 secao 15).
  """
  @spec criar_pasta(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), keyword()) ::
          {:ok, Folder.t()} | {:error, term()}
  def criar_pasta(repo, keys, %Scope{} = scope, nome, opts \\ []) do
    case resolve_folder(repo, scope, opts[:parent]) do
      {:ok, parent} -> commit_folder(repo, keys, scope, nome, parent)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  O arquivo pelo rkey, sob a regra de leitura: casa alheia sem concessao
  responde {:error, :forbidden}, rkey inexistente responde {:error, :not_found}.
  """
  @spec get_file(Ecto.Repo.t(), Scope.t(), String.t()) ::
          {:ok, File.t()} | {:error, :not_found | :forbidden}
  def get_file(repo, %Scope{} = scope, rkey) do
    get_readable(repo, scope, "ypy.file.v0", rkey)
  end

  @doc "A pasta pelo rkey, sob a regra de leitura."
  @spec get_folder(Ecto.Repo.t(), Scope.t(), String.t()) ::
          {:ok, Folder.t()} | {:error, :not_found | :forbidden}
  def get_folder(repo, %Scope{} = scope, rkey) do
    get_readable(repo, scope, "ypy.folder.v0", rkey)
  end

  @doc """
  Os arquivos legiveis pela regra (praca OU dono OU concessao), do mais
  recente para o mais antigo. Opcoes: `:folder` (rkey), `:zona`, `:cursor`
  (rkey do ultimo item), `:limit` e `:lixeira`.
  """
  @spec list_files(Ecto.Repo.t(), Scope.t(), keyword()) :: [File.t()]
  def list_files(repo, %Scope{} = scope, opts \\ []) do
    case resolve_folder(repo, scope, opts[:folder]) do
      {:ok, folder} ->
        query =
          scope.tekoa.id
          |> Queries.files(Keyword.put(opts, :folder, folder && folder.id))
          |> Queries.readable(scope)

        repo.all(query)

      {:error, _} ->
        []
    end
  end

  @doc "As pastas legiveis, mesmo jogo das listagens. Opcoes: `:parent`, `:zona`, `:cursor`, `:limit`, `:lixeira`."
  @spec list_folders(Ecto.Repo.t(), Scope.t(), keyword()) :: [Folder.t()]
  def list_folders(repo, %Scope{} = scope, opts \\ []) do
    case resolve_folder(repo, scope, opts[:parent]) do
      {:ok, parent} ->
        query =
          scope.tekoa.id
          |> Queries.folders(Keyword.put(opts, :parent, parent && parent.id))
          |> Queries.readable_folder(scope)

        repo.all(query)

      {:error, _} ->
        []
    end
  end

  @doc "Manda o recurso para a lixeira (soft delete). So o dono."
  @spec apagar(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t()) ::
          {:ok, File.t() | Folder.t()} | {:error, term()}
  def apagar(repo, keys, %Scope{} = scope, tipo, rkey) do
    mutar(repo, keys, scope, tipo, rkey, "apagar", fn row ->
      agora = DateTime.truncate(DateTime.utc_now(), :second)
      repo.update(change(row, apagado_em: agora))
    end)
  end

  @doc "Tira da lixeira. So o dono."
  @spec restaurar(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t()) ::
          {:ok, File.t() | Folder.t()} | {:error, term()}
  def restaurar(repo, keys, %Scope{} = scope, tipo, rkey) do
    with {:ok, row} <- recurso(repo, scope.tekoa.id, tipo, rkey, true),
         :ok <- owner_guard(row, scope),
         {:ok, row} <- linha_na_lixeira(row) do
      mutar_row(repo, keys, scope, tipo, row, "restaurar", fn row ->
        repo.update(change(row, apagado_em: nil))
      end)
    end
  end

  defp linha_na_lixeira(%{apagado_em: nil}), do: {:error, :invalid_status}
  defp linha_na_lixeira(row), do: {:ok, row}

  @doc """
  Publica na praca (RFC_003 secao 2): colocar na praca E o ato de
  consentimento, agora uma entrada assinada. So o dono; idempotente no no-op.
  """
  @spec publicar(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t()) ::
          {:ok, File.t() | Folder.t()} | {:error, term()}
  def publicar(repo, keys, %Scope{} = scope, tipo, rkey) do
    mudar_zona(repo, keys, scope, tipo, rkey, :praca, "publicar")
  end

  @doc "Tira da praca, de volta para a casa. So o dono; idempotente no no-op."
  @spec tirar_da_praca(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t()) ::
          {:ok, File.t() | Folder.t()} | {:error, term()}
  def tirar_da_praca(repo, keys, %Scope{} = scope, tipo, rkey) do
    mudar_zona(repo, keys, scope, tipo, rkey, :casa, "tirar_da_praca")
  end

  @doc """
  Move o arquivo para a pasta de rkey dado (ou nil, para solto). A pasta de
  destino precisa ser do dono; a zona nao cascateia (RFC_003 D1).
  """
  @spec mover(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t() | nil) ::
          {:ok, File.t()} | {:error, term()}
  def mover(repo, keys, %Scope{} = scope, rkey, folder_rkey) do
    with {:ok, file} <- recurso(repo, scope.tekoa.id, "ypy.file.v0", rkey),
         :ok <- owner_guard(file, scope),
         {:ok, folder} <- resolve_folder(repo, scope, folder_rkey),
         payload =
           file_payload(file.nome, folder && folder.rkey, file.mime, file.tamanho, file.blob_cid),
         {:ok, {cid, _} = envelope} <- nova_versao(scope, "ypy.file.v0", rkey, payload) do
      commit_versao(repo, keys, scope, "ypy.file.v0", file, envelope, "mover", fn file ->
        File.record_changeset(file, %{cid: cid, nome: file.nome, folder_id: folder && folder.id})
      end)
    end
  end

  @doc "Renomeia (o nome do record, nao os bytes). So o dono."
  @spec renomear(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t(), String.t()) ::
          {:ok, File.t() | Folder.t()} | {:error, term()}
  def renomear(repo, keys, %Scope{} = scope, tipo, rkey, nome) do
    with {:ok, row} <- recurso(repo, scope.tekoa.id, tipo, rkey),
         :ok <- owner_guard(row, scope),
         {:ok, payload} <- payload_para(repo, row, tipo, nome),
         {:ok, {cid, _} = envelope} <- nova_versao(scope, tipo, rkey, payload) do
      commit_versao(repo, keys, scope, tipo, row, envelope, "renomear", fn row ->
        record_changeset(row, %{cid: cid, nome: nome})
      end)
    end
  end

  defp get_readable(repo, scope, tipo, rkey) do
    with {:ok, row} <- recurso(repo, scope.tekoa.id, tipo, rkey) do
      if read_rule?(repo, scope, row), do: {:ok, row}, else: {:error, :forbidden}
    end
  end

  defp read_rule?(repo, scope, row) do
    concessoes = MaracaStore.concessoes_ativas(repo, scope.tekoa.id, scope.ava.id)
    Policy.can_read?(row.zona, scope.ava.id, row.dono_id, tipo_do_row(row), row.rkey, concessoes)
  end

  # A concessao vale pelo tipo de colecao, como no SQL das listagens: o
  # rkey sozinho nao abre a porta.
  defp tipo_do_row(%File{}), do: "ypy.file.v0"
  defp tipo_do_row(%Folder{}), do: "ypy.folder.v0"

  defp fetch_tekoa(repo, scope) do
    if tekoa = MaracaStore.get_tekoa(repo, scope.tekoa.id),
      do: {:ok, tekoa},
      else: {:error, :not_found}
  end

  defp fetch_mime(opts) do
    case Keyword.fetch(opts, :mime) do
      {:ok, mime} when is_binary(mime) -> {:ok, mime}
      :error -> {:error, :missing_mime}
    end
  end

  defp mime_allowed?(mime, opts) do
    if mime in Keyword.get(opts, :allowed_mimes, @allowed_mimes),
      do: :ok,
      else: {:error, :mime_not_allowed}
  end

  defp quota_ok?(_repo, %{storage_quota_bytes: nil}, _size), do: :ok

  defp quota_ok?(_repo, %{storage_quota_bytes: quota, storage_used_bytes: used}, size) when is_integer(quota) do
    if used + size > quota, do: {:error, :storage_quota_exceeded}, else: :ok
  end

  # A pasta de destino, quando ha, e resolvida e tem de ser do dono: subir
  # numa pasta da praca alheia e o achado da RFC_005 secao 15, consertado
  # aqui na borda.
  defp resolve_folder(_repo, _scope, nil), do: {:ok, nil}

  defp resolve_folder(repo, scope, rkey) do
    with {:ok, folder} <- recurso(repo, scope.tekoa.id, "ypy.folder.v0", rkey),
         :ok <- owner_guard(folder, scope) do
      {:ok, folder}
    end
  end

  defp nome(path, opts), do: Keyword.get(opts, :nome, Path.basename(path))

  # O payload auto-descritivo do record de arquivo (RFC_006 secao 6): a
  # cadeia reconstrui o arquivo dele. A zona fica de fora (coluna tipada
  # local, casa nao federa) e a pasta solta nao leva chave.
  defp file_payload(nome, nil, mime, size, blob) do
    %{"name" => nome, "mime_type" => mime, "size_bytes" => size, "blob" => blob}
  end

  defp file_payload(nome, folder_rkey, mime, size, blob) do
    nome
    |> file_payload(nil, mime, size, blob)
    |> Map.put("folder", folder_rkey)
  end

  # O payload atual do recurso, com o nome novo: a base da versao no
  # renomear. A pasta do arquivo entra pela chave "folder" do lexicon.
  defp payload_para(repo, row, "ypy.file.v0", nome) do
    {:ok,
     file_payload(
       nome,
       Store.folder_rkey(repo, row.folder_id),
       row.mime,
       row.tamanho,
       row.blob_cid
     )}
  end

  defp payload_para(_repo, _row, "ypy.folder.v0", nome), do: {:ok, %{"name" => nome}}

  defp nova_versao(scope, tipo, rkey, payload) do
    actor = Handle.of(scope.ava.username, scope.tekoa.domain)
    versao(tipo, rkey, actor, payload)
  end

  # Grava a versao nova do envelope e o dado que ela descreve, com a entrada
  # na cadeia, numa transacao so (RFC_006 secao 8).
  defp commit_versao(repo, keys, scope, tipo, row, {cid, wire}, entrada, changeset_fn) do
    Mural.Store.commit(
      repo,
      keys,
      scope.tekoa.id,
      entrada,
      %{
        "actor" => scope.ava.public_id,
        "collection" => tipo,
        "rkey" => row.rkey
      },
      fn ->
        with {:ok, _} <-
               commit_record(repo, scope, row.rkey, tipo, cid, wire) do
          repo.update(changeset_fn.(row))
        end
      end
    )
  end

  defp commit_record(repo, scope, rkey, tipo, cid, wire) do
    repo.insert(
      RecordRow.changeset(%RecordRow{}, %{
        tekoa_id: scope.tekoa.id,
        rkey: rkey,
        collection: tipo,
        cid: cid,
        record: wire
      })
    )
  end

  defp commit_upload(repo, keys, blobs, scope, tekoa, path, meta) do
    case blob_put_file(blobs, path) do
      {:ok, blob_cid} ->
        # O hash e o digest do proprio CID (sha2-256 raw), em hex minusculo:
        # nenhum segundo calculo sobre bytes na memoria.
        hash = Base.encode16(blob_cid.digest, case: :lower)
        upload = Map.merge(meta, %{blob_cid: blob_cid, hash: hash})

        case commit_upload_rows(repo, keys, scope, tekoa, upload) do
          {:ok, file} ->
            {:ok, file}

          {:error, reason} ->
            # Os bytes sao enderecados por conteudo e deduplicados: so saem
            # quando nenhuma linha da Tekoa os endereca.
            recolher_bytes_orfaos(repo, blobs, tekoa.id, blob_cid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # O upload falhou e o rollback devolveu o dado: a linha do blob que
  # sobrevive ao rollback e a de um upload anterior que a commitou (um
  # arquivo vivo ainda a usa); sem linha na Tekoa, os bytes nao sao de
  # ninguem e saem.
  defp recolher_bytes_orfaos(repo, blobs, tekoa_id, blob_cid) do
    if Store.get_blob(repo, tekoa_id, Cid.to_string(blob_cid)) do
      :ok
    else
      _ = blob_delete(blobs, blob_cid)
      :ok
    end
  end

  defp commit_upload_rows(repo, keys, scope, tekoa, upload) do
    rkey = Tid.now()
    actor = Handle.of(scope.ava.username, tekoa.domain)
    blob = Cid.to_string(upload.blob_cid)

    payload =
      file_payload(
        upload.nome,
        upload.folder && upload.folder.rkey,
        upload.mime,
        upload.size,
        blob
      )

    case versao("ypy.file.v0", rkey, actor, payload) do
      {:ok, {cid_string, wire}} ->
        hash = upload.hash

        entrada = %{
          "actor" => scope.ava.public_id,
          "collection" => "ypy.file.v0",
          "rkey" => rkey,
          "cid" => cid_string,
          "blob" => blob,
          "mime" => upload.mime,
          "hash" => hash,
          "tamanho" => upload.size
        }

        put = %{rkey: rkey, cid: cid_string, blob: blob, wire: wire, hash: hash}

        Mural.Store.commit(repo, keys, tekoa.id, "put", entrada, fn ->
          write_upload(repo, scope, tekoa, upload, put)
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_upload(repo, scope, tekoa, upload, %{rkey: rkey, cid: cid, blob: blob, wire: wire, hash: hash}) do
    with {:ok, _} <-
           Store.put_blob(
             repo,
             Blob.changeset(%Blob{}, %{
               tekoa_id: tekoa.id,
               cid: blob,
               tamanho: upload.size,
               hash: hash
             })
           ),
         {:ok, _} <- commit_record(repo, scope, rkey, "ypy.file.v0", cid, wire),
         {:ok, file} <-
           repo.insert(
             File.changeset(%File{}, %{
               tekoa_id: tekoa.id,
               dono_id: scope.ava.id,
               rkey: rkey,
               cid: cid,
               blob_cid: blob,
               nome: upload.nome,
               mime: upload.mime,
               tamanho: upload.size,
               hash: hash,
               folder_id: upload.folder && upload.folder.id,
               zona: :casa
             })
           ),
         # A cota vale pelo estado no momento da escrita: o caminho rapido la
         # fora pode ter visto lugar que um upload concorrente ja ocupou, e o
         # used e relido aqui dentro, antes de somar. Estourar agora desfaz a
         # transacao inteira (RFC_006 secao 8).
         {:ok, tekoa_agora} <- fetch_tekoa(repo, scope),
         :ok <- quota_ok?(repo, tekoa_agora, upload.size),
         :ok <- MaracaStore.add_storage(repo, tekoa.id, upload.size) do
      {:ok, file}
    end
  end

  # O envelope montado, checado contra o lexicon e enderecado: o par
  # {cid string, wire} que o commit grava. Os erros do check/2 chegam
  # taggeados para a borda: quando todo erro e de payload, o envelope esta
  # bom e o payload nao, e o tag e {:payload_invalido, erros}, com o
  # "payload" do caminho tirado, como o validador entregou; erro de forma do
  # envelope junto, ou colecao desconhecida, e {:envelope_invalido, motivo}.
  defp versao(tipo, rkey, actor, payload) do
    record =
      Record.build(
        type: tipo,
        rkey: rkey,
        actor: actor,
        created_at: now_micros(),
        payload: payload
      )

    case Record.check(record, Registry.record(tipo)) do
      :ok ->
        {_bytes, cid} = Record.encode(record)
        {:ok, {Cid.to_string(cid), Record.to_wire(record)}}

      {:error, :unknown_collection} ->
        {:error, {:envelope_invalido, :unknown_collection}}

      {:error, errors} ->
        if so_de_payload?(errors) do
          {:error, {:payload_invalido, Enum.map(errors, &tirar_prefixo/1)}}
        else
          {:error, {:envelope_invalido, errors}}
        end
    end
  end

  defp so_de_payload?(errors) do
    Enum.all?(errors, fn
      {["payload" | _], _} -> true
      _ -> false
    end)
  end

  defp tirar_prefixo({["payload" | path], reason}), do: {path, reason}

  defp commit_folder(repo, keys, scope, nome, parent) do
    rkey = Tid.now()
    actor = Handle.of(scope.ava.username, scope.tekoa.domain)

    case versao("ypy.folder.v0", rkey, actor, %{"name" => nome}) do
      {:ok, {cid_string, wire}} ->
        entrada = %{
          "actor" => scope.ava.public_id,
          "collection" => "ypy.folder.v0",
          "rkey" => rkey,
          "cid" => cid_string
        }

        Mural.Store.commit(repo, keys, scope.tekoa.id, "put", entrada, fn ->
          write_folder(repo, scope, rkey, cid_string, wire, nome, parent)
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_folder(repo, scope, rkey, cid, wire, nome, parent) do
    with {:ok, _} <- commit_record(repo, scope, rkey, "ypy.folder.v0", cid, wire) do
      repo.insert(
        Folder.changeset(%Folder{}, %{
          tekoa_id: scope.tekoa.id,
          dono_id: scope.ava.id,
          rkey: rkey,
          cid: cid,
          nome: nome,
          zona: :casa,
          parent_id: parent && parent.id
        })
      )
    end
  end

  # O trilho comum dos verbos de mutacao simples: resolve o recurso fora da
  # lixeira, cobra o dono, aplica o changeset e anexa a entrada na cadeia.
  defp mutar(repo, keys, scope, tipo, rkey, entrada, aplicar) do
    with {:ok, row} <- recurso(repo, scope.tekoa.id, tipo, rkey),
         :ok <- owner_guard(row, scope) do
      mutar_row(repo, keys, scope, tipo, row, entrada, aplicar)
    end
  end

  defp mutar_row(repo, keys, scope, tipo, row, entrada, aplicar) do
    Mural.Store.commit(
      repo,
      keys,
      scope.tekoa.id,
      entrada,
      %{
        "actor" => scope.ava.public_id,
        "collection" => tipo,
        "rkey" => row.rkey
      },
      fn ->
        aplicar.(row)
      end
    )
  end

  defp mudar_zona(repo, keys, scope, tipo, rkey, zona, entrada) do
    with {:ok, row} <- recurso(repo, scope.tekoa.id, tipo, rkey),
         :ok <- owner_guard(row, scope) do
      mudar_zona_row(repo, keys, scope, tipo, row, zona, entrada)
    end
  end

  defp mudar_zona_row(_repo, _keys, _scope, _tipo, %{zona: zona} = row, zona, _entrada), do: {:ok, row}

  defp mudar_zona_row(repo, keys, scope, tipo, row, zona, entrada) do
    mutar_row(repo, keys, scope, tipo, row, entrada, &repo.update(change(&1, zona: zona)))
  end

  defp owner_guard(row, scope) do
    if row.dono_id == scope.ava.id, do: :ok, else: {:error, :not_owner}
  end

  # O changeset de record pelo struct: arquivo e pasta tem changesets
  # diferentes para a mesma versao nova do envelope.
  defp record_changeset(%File{} = row, attrs), do: File.record_changeset(row, attrs)
  defp record_changeset(%Folder{} = row, attrs), do: Folder.record_changeset(row, attrs)

  defp now_micros, do: System.os_time(:microsecond)

  # A impl mora no struct; o modulo behaviour nao tem callback nenhum.
  defp blob_put_file(blobs, path) do
    impl = impl(blobs)

    # O upload grande transmite: quando a impl sabe receber um arquivo (o
    # callback opcional put_file/2), os bytes nem passam pela memoria;
    # quando nao sabe, lemos o arquivo inteiro e vamos de put/2.
    if function_exported?(impl, :put_file, 2) do
      impl.put_file(blobs, path)
    else
      with {:ok, data} <- Elixir.File.read(path) do
        impl.put(blobs, data)
      end
    end
  end

  defp blob_delete(blobs, cid), do: impl(blobs).delete(blobs, cid)
  defp impl(store), do: store.__struct__
end
