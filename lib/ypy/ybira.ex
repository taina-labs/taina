defmodule Ypy.Ybira do
  @moduledoc """
  Os verbos sociais do armazenamento: upload, leitura com a regra das duas
  zonas, lixeira, publicar e tirar da praca, mover e renomear.

  Todo verbo que muda estado anexa uma entrada na cadeia (RFC_006 secao 8): o
  mural e a projecao social da mesma lista que sustenta os records. Dado e
  cadeia entram no mesmo commit: uma falha de cadeia desfaz a escrita, e o
  que commitou tem entrada na cadeia.
  """

  alias Ypy.BlobStore
  alias Ypy.Cid
  alias Ypy.KeyStore
  alias Ypy.Lexicon.Registry
  alias Ypy.Lexicon.Validate
  alias Ypy.Maraca.Policy
  alias Ypy.Maraca.Store, as: MaracaStore
  alias Ypy.Mural
  alias Ypy.Record
  alias Ypy.Scope
  ## Recurso generico (arquivo ou pasta)
  alias Ypy.Ybira.Blob
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder
  alias Ypy.Ybira.Queries
  alias Ypy.Ybira.Record, as: RecordRow
  alias Ypy.Ybira.Store

  @max_attempts 3

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

  ## Arquivos

  def recurso(repo, tekoa_id, tipo, rkey, lixeira?) when is_map_key(@tipos, tipo) do
    row =
      case @tipos[tipo] do
        File -> Store.get_file(repo, tekoa_id, rkey, lixeira?)
        Folder -> Store.get_folder(repo, tekoa_id, rkey, lixeira?)
      end

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
    with {:ok, parent} <- resolve_folder(repo, scope, opts[:parent]),
         :ok <- payload_ok?("ypy.folder.v0", %{"name" => nome}) do
      commit_folder(repo, keys, scope, nome, parent)
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

  ## Lixeira
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

        ## Zona
        Store.all(repo, query)

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

        ## Move e rename

        Store.all(repo, query)

      {:error, _} ->
        []
    end
  end

  @doc "Manda o recurso para a lixeira (soft delete). So o dono."
  @spec apagar(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t()) ::
          {:ok, File.t() | Folder.t()} | {:error, term()}
  def apagar(repo, keys, %Scope{} = scope, tipo, rkey) do
    mutar(repo, keys, scope, tipo, rkey, "apagar", fn row, agora ->
      Store.update(repo, changeset_de(tipo, :trash, row, agora))
    end)
  end

  @doc "Tira da lixeira. So o dono."
  @spec restaurar(Ecto.Repo.t(), KeyStore.t(), Scope.t(), String.t(), String.t()) ::
          {:ok, File.t() | Folder.t()} | {:error, term()}
  def restaurar(repo, keys, %Scope{} = scope, tipo, rkey) do
    with {:ok, row} <- recurso(repo, scope.tekoa.id, tipo, rkey, true),
         {:ok, row} <- linha_na_lixeira(row) do
      mutar_row(repo, keys, scope, tipo, row, "restaurar", restaurar_upsert(repo, tipo, row))
    end
  end

  defp linha_na_lixeira(%{apagado_em: nil}), do: {:error, :invalid_status}
  defp linha_na_lixeira(row), do: {:ok, row}

  defp restaurar_upsert(repo, tipo, row) do
    fn _row, _agora -> Store.update(repo, changeset_de(tipo, :restore, row, nil)) end
  end

  ## Internos

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
         :ok <- payload_ok?("ypy.file.v0", payload),
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
         :ok <- payload_ok?(tipo, payload),
         {:ok, {cid, _} = envelope} <- nova_versao(scope, tipo, rkey, payload) do
      commit_versao(repo, keys, scope, tipo, row, envelope, "renomear", fn row ->
        changeset_de(tipo, :record, row, %{cid: cid, nome: nome})
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
    Policy.can_read?(row.zona, scope.ava.id, row.dono_id, row.rkey, concessoes)
  end

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

  defp payload_ok?(tipo, payload) do
    case Validate.validate(Registry.record(tipo), payload) do
      :ok -> :ok
      {:error, errors} -> {:error, {:payload_invalido, errors}}
    end
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
    actor = "#{scope.ava.username}@#{scope.tekoa.domain}"

    case versao(tipo, rkey, actor, payload) do
      {:ok, par} -> {:ok, par}
      {:error, reason} -> {:error, {:envelope_invalido, reason}}
    end
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
    Store.insert_record(
      repo,
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

        case commit_upload_rows(repo, keys, scope, tekoa, upload, @max_attempts) do
          {:ok, file} ->
            {:ok, file}

          {:error, reason} ->
            _ = blob_delete(blobs, blob_cid)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_upload_rows(_repo, _keys, _scope, _tekoa, _upload, 0), do: {:error, :rkey_conflict}

  defp commit_upload_rows(repo, keys, scope, tekoa, upload, attempts) do
    rkey = File.next_rkey()
    actor = "#{scope.ava.username}@#{tekoa.domain}"
    blob = Cid.to_string(upload.blob_cid)

    payload =
      file_payload(
        upload.nome,
        upload.folder && upload.folder.rkey,
        upload.mime,
        upload.size,
        blob
      )

    with :ok <- payload_ok?("ypy.file.v0", payload),
         {:ok, {cid_string, wire}} <- versao("ypy.file.v0", rkey, actor, payload) do
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

      result =
        Mural.Store.commit(repo, keys, tekoa.id, "put", entrada, fn ->
          write_upload(repo, scope, tekoa, upload, put)
        end)

      upload_result(repo, keys, scope, tekoa, upload, attempts, result)
    else
      {:error, {:payload_invalido, _}} = error -> error
      {:error, reason} -> {:error, {:envelope_invalido, reason}}
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
           Store.insert_file(
             repo,
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
         :ok <- MaracaStore.add_storage(repo, tekoa.id, upload.size) do
      {:ok, file}
    end
  end

  defp upload_result(_repo, _keys, _scope, _tekoa, _upload, _attempts, {:ok, file}), do: {:ok, file}

  defp upload_result(repo, keys, scope, tekoa, upload, attempts, {:error, %Ecto.Changeset{} = changeset}) do
    if unique_conflict?(changeset) and attempts > 1 do
      commit_upload_rows(repo, keys, scope, tekoa, upload, attempts - 1)
    else
      {:error, changeset}
    end
  end

  defp upload_result(_repo, _keys, _scope, _tekoa, _upload, _attempts, {:error, reason}), do: {:error, reason}

  # O envelope montado, checado contra o lexicon e enderecado: o par
  # {cid string, wire} que o commit grava.
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
        {:ok, {Cid.to_string(cid), wire_map(record)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit_folder(repo, keys, scope, nome, parent, attempts \\ @max_attempts)

  defp commit_folder(_repo, _keys, _scope, _nome, _parent, 0), do: {:error, :rkey_conflict}

  defp commit_folder(repo, keys, scope, nome, parent, attempts) do
    rkey = Folder.next_rkey()
    actor = "#{scope.ava.username}@#{scope.tekoa.domain}"

    case versao("ypy.folder.v0", rkey, actor, %{"name" => nome}) do
      {:ok, {cid_string, wire}} ->
        entrada = %{
          "actor" => scope.ava.public_id,
          "collection" => "ypy.folder.v0",
          "rkey" => rkey,
          "cid" => cid_string
        }

        result =
          Mural.Store.commit(repo, keys, scope.tekoa.id, "put", entrada, fn ->
            write_folder(repo, scope, rkey, cid_string, wire, nome, parent)
          end)

        folder_result(repo, keys, scope, nome, parent, attempts, result)

      {:error, reason} ->
        {:error, {:envelope_invalido, reason}}
    end
  end

  defp folder_result(_repo, _keys, _scope, _nome, _parent, _attempts, {:ok, folder}), do: {:ok, folder}

  defp folder_result(repo, keys, scope, nome, parent, attempts, {:error, %Ecto.Changeset{} = changeset}) do
    if unique_conflict?(changeset) and attempts > 1 do
      commit_folder(repo, keys, scope, nome, parent, attempts - 1)
    else
      {:error, changeset}
    end
  end

  defp folder_result(_repo, _keys, _scope, _nome, _parent, _attempts, {:error, reason}), do: {:error, reason}

  defp write_folder(repo, scope, rkey, cid, wire, nome, parent) do
    with {:ok, _} <- commit_record(repo, scope, rkey, "ypy.folder.v0", cid, wire) do
      Store.insert_folder(
        repo,
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
        aplicar.(row, DateTime.truncate(DateTime.utc_now(), :second))
      end
    )
  end

  defp mudar_zona(repo, keys, scope, tipo, rkey, zona, entrada) do
    with {:ok, row} <- recurso(repo, scope.tekoa.id, tipo, rkey),
         :ok <- owner_guard(row, scope) do
      if row.zona == zona do
        {:ok, row}
      else
        mutar_row(repo, keys, scope, tipo, row, entrada, zona_upsert(repo, tipo, zona))
      end
    end
  end

  defp zona_upsert(repo, tipo, zona) do
    fn row, _agora -> Store.update(repo, changeset_de(tipo, :zona, row, zona)) end
  end

  defp owner_guard(row, scope) do
    if row.dono_id == scope.ava.id, do: :ok, else: {:error, :not_owner}
  end

  defp changeset_de(tipo, :trash, row, agora), do: trash_changeset(tipo, row, agora)
  defp changeset_de(tipo, :restore, row, nil), do: restore_changeset(tipo, row)
  defp changeset_de(tipo, :zona, row, zona), do: zona_changeset(tipo, row, zona)
  defp changeset_de(tipo, :record, row, attrs), do: record_changeset(tipo, row, attrs)

  defp trash_changeset("ypy.file.v0", row, agora), do: File.trash_changeset(row, agora)
  defp trash_changeset("ypy.folder.v0", row, agora), do: Folder.trash_changeset(row, agora)

  defp restore_changeset("ypy.file.v0", row), do: File.restore_changeset(row)
  defp restore_changeset("ypy.folder.v0", row), do: Folder.restore_changeset(row)

  defp zona_changeset("ypy.file.v0", row, zona), do: File.zona_changeset(row, zona)
  defp zona_changeset("ypy.folder.v0", row, zona), do: Folder.zona_changeset(row, zona)

  defp record_changeset("ypy.file.v0", row, attrs), do: File.record_changeset(row, attrs)
  defp record_changeset("ypy.folder.v0", row, attrs), do: Folder.record_changeset(row, attrs)

  defp unique_conflict?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {_field, {_message, [constraint: :unique, constraint_name: _]}} -> true
      _ -> false
    end)
  end

  defp wire_map(%Record{} = record) do
    %{
      "$type" => record.type,
      "rkey" => record.rkey,
      "actor" => record.actor,
      "created_at" => record.created_at,
      "payload" => record.payload
    }
  end

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
