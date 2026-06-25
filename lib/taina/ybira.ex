defmodule Taina.Ybira do
  @moduledoc """
  Ybira, sistema de arquivos da comunidade.

  Implementa `Taina.Ybira.Behaviour`, as regras de negócio de cada função estão
  documentadas lá, nos `@callback`.

  Todas as funções públicas recebem um `Taina.Scope` (quem + qual Tekoa) e
  executam dentro de `Repo.with_tekoa/2`, ativando o isolamento RLS. A exceção é
  `purge_deleted_files/1`, operação de sistema que atravessa todas as Tekoas.

  Os bytes ficam no disco em
  `{storage_root}/{tekoa_public_id}/files/{ano}/{mes}/{nome}.{ext}`;
  o banco guarda apenas metadados. `storage_root` vem de
  `config :taina, :storage_root`.

  ## Lixeira (soft delete)

  Deletar um arquivo ou pasta só preenche `deleted_at`, os bytes ficam no disco
  e a cota não é devolvida na hora. O worker `Taina.Ybira.Workers.PurgeTrash`
  apaga de vez o que está na lixeira há mais de 30 dias e só então recupera a
  cota. Até lá, `restore_file/2` traz o arquivo de volta.

  ## Paginação

  Listagens usam cursor por keyset (`id` decrescente, equivalente a
  `inserted_at DESC, id DESC` já que o `id` é serial monótono). O cursor é opaco
  (`Base.url_encode64`); passe-o de volta em `:after_cursor` para a próxima
  página.
  """

  @behaviour Taina.Ybira.Behaviour

  import Ecto.Query

  alias Taina.Maraca
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa
  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira
  alias Taina.Ybira.MimeDetector
  alias Taina.Ybira.Workers.Rendition

  require Logger

  @hash_chunk_bytes 1024 * 1024
  @default_limit 50

  # Tipos MIME aceitos no upload. Detectados pelos magic bytes (não pela
  # extensão); `application/octet-stream` cobre binários desconhecidos, mas
  # executáveis são detectados e ficam de fora, logo, rejeitados.
  @allowed_mime_types ~w[
    image/jpeg image/png image/gif image/webp image/heic image/heif
    video/mp4 video/quicktime video/webm video/avi
    audio/mpeg audio/ogg audio/wav audio/flac
    application/pdf application/zip application/octet-stream
    text/plain
  ]

  ## Upload

  @impl true
  def upload(%Scope{} = scope, tmp_path, opts \\ []) do
    original_filename = Keyword.get(opts, :filename, Path.basename(tmp_path))
    folder_id = Keyword.get(opts, :folder_id)
    mime_type = MimeDetector.detect(tmp_path)

    with {:ok, %{size: size}} <- Elixir.File.stat(tmp_path),
         :ok <- validate_mime(mime_type),
         {:ok, hash} <- hash_file(tmp_path),
         {:ok, dest} <- copy_to_storage(scope, tmp_path, original_filename) do
      attrs = %{
        filename: Path.basename(dest),
        original_filename: original_filename,
        filepath: dest,
        mime_type: mime_type,
        file_size_bytes: size,
        file_hash: hash,
        ava_id: scope.ava.id,
        tekoa_id: scope.tekoa.id,
        folder_id: folder_id
      }

      case insert_within_quota(scope, attrs, size) do
        {:ok, file} ->
          {:ok, file}

        {:error, reason} ->
          Elixir.File.rm(dest)
          {:error, reason}
      end
    end
  end

  defp validate_mime(mime) when mime in @allowed_mime_types, do: :ok
  defp validate_mime(_mime), do: {:error, :mime_not_allowed}

  defp insert_within_quota(%Scope{} = scope, attrs, size) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with :ok <- quota_check(scope.tekoa.id, size),
           {:ok, file} <- Repo.insert(Ybira.File.changeset(%Ybira.File{}, attrs)) do
        adjust_storage_used(scope.tekoa.id, size)
        maybe_enqueue_rendition(scope, file)
        {:ok, file}
      end
    end)
  end

  # Imagens ganham thumbnails + metadados (dimensões, EXIF) num job pós-upload.
  # Enfileirado na mesma transação do insert: só roda se o upload commitar, e o
  # job só toca o disco/banco depois (a fila do Oban é isenta de RLS, ver
  # `Repo.prepare_query/3`). Em testes (`testing: :inline`) ele roda na hora.
  defp maybe_enqueue_rendition(%Scope{} = scope, %Ybira.File{} = file) do
    if image?(file.mime_type) do
      %{file_id: file.id, tekoa_public_id: scope.tekoa.public_id}
      |> Rendition.new()
      |> Oban.insert()
    end
  end

  defp image?("image/" <> _rest), do: true
  defp image?(_mime), do: false

  ## Arquivos

  @impl true
  def get_file(%Scope{} = scope, file_public_id) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      query =
        from f in Ybira.File,
          where: f.public_id == ^file_public_id and is_nil(f.deleted_at)

      case Repo.one(query) do
        nil -> {:error, :not_found}
        file -> authorize_read(scope, "ybira_file", file)
      end
    end)
  end

  @impl true
  def list_files(%Scope{} = scope, folder_public_id \\ nil, opts \\ []) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      base =
        from f in Ybira.File,
          as: :readable,
          where: is_nil(f.deleted_at),
          where: ^Maraca.readable_dynamic(scope.ava, "ybira_file"),
          order_by: [desc: f.inserted_at, desc: f.id]

      query =
        case folder_public_id do
          nil ->
            from f in base, where: is_nil(f.folder_id)

          public_id when is_binary(public_id) ->
            from f in base,
              join: d in Ybira.Folder,
              on: d.id == f.folder_id,
              where: d.public_id == ^public_id
        end

      {items, next_cursor} = fetch_page(query, opts)
      {:ok, %{items: items, next_cursor: next_cursor}}
    end)
  end

  @impl true
  def delete_file(%Scope{} = scope, file_public_id) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      query =
        from f in Ybira.File,
          where: f.public_id == ^file_public_id,
          where: f.ava_id == ^scope.ava.id,
          where: is_nil(f.deleted_at)

      case Repo.one(query) do
        nil -> {:error, :not_found}
        file -> Repo.update(Ybira.File.delete_changeset(file))
      end
    end)
  end

  @impl true
  def restore_file(%Scope{} = scope, file_public_id) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      query =
        from f in Ybira.File,
          where: f.public_id == ^file_public_id and not is_nil(f.deleted_at)

      file = Repo.one(query)

      if file && owner?(scope, file.ava_id) do
        Repo.update(Ybira.File.restore_changeset(file))
      else
        {:error, :not_found}
      end
    end)
  end

  @impl true
  def list_trash(%Scope{} = scope, opts \\ []) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      query =
        from f in Ybira.File,
          where: not is_nil(f.deleted_at) and f.ava_id == ^scope.ava.id,
          order_by: [desc: f.inserted_at, desc: f.id]

      {items, next_cursor} = fetch_page(query, opts)
      {:ok, %{items: items, next_cursor: next_cursor}}
    end)
  end

  @impl true
  def rename_file(%Scope{} = scope, file_public_id, new_name) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, file} <- fetch_owned_file(scope, file_public_id) do
        Repo.update(Ybira.File.rename_changeset(file, new_name))
      end
    end)
  end

  @impl true
  def move_file(%Scope{} = scope, file_public_id, folder_public_id) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, file} <- fetch_owned_file(scope, file_public_id),
           {:ok, folder_id} <- resolve_folder_id(folder_public_id) do
        Repo.update(Ybira.File.changeset(file, %{folder_id: folder_id}))
      end
    end)
  end

  @impl true
  def publicar_file(%Scope{} = scope, file_public_id) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, file} <- fetch_owned_file(scope, file_public_id) do
        Repo.update(Ybira.File.zona_changeset(file, :praca))
      end
    end)
  end

  @impl true
  def tirar_file_da_praca(%Scope{} = scope, file_public_id) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, file} <- fetch_owned_file(scope, file_public_id) do
        Repo.update(Ybira.File.zona_changeset(file, :casa))
      end
    end)
  end

  ## Pastas

  @impl true
  def create_folder(%Scope{} = scope, attrs) when is_map(attrs) do
    name = fetch_attr(attrs, :name)
    parent_public_id = fetch_attr(attrs, :parent_public_id)

    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, parent_id} <- resolve_folder_id(parent_public_id) do
        Repo.insert(
          Ybira.Folder.changeset(%Ybira.Folder{}, %{
            name: name,
            parent_id: parent_id,
            ava_id: scope.ava.id,
            tekoa_id: scope.tekoa.id
          })
        )
      end
    end)
  end

  @impl true
  def get_folder(%Scope{} = scope, public_id) when is_binary(public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      case Repo.one(folder_by_public_id(public_id)) do
        nil -> {:error, :not_found}
        folder -> authorize_read(scope, "ybira_folder", folder)
      end
    end)
  end

  @impl true
  def rename_folder(%Scope{} = scope, public_id, new_name) when is_binary(public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, folder} <- fetch_folder(scope, public_id) do
        Repo.update(Ybira.Folder.changeset(folder, %{name: new_name}))
      end
    end)
  end

  @impl true
  def move_folder(%Scope{} = scope, public_id, new_parent_public_id) when is_binary(public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, folder} <- fetch_folder(scope, public_id),
           {:ok, new_parent_id} <- resolve_folder_id(new_parent_public_id),
           :ok <- ensure_acyclic(folder.id, new_parent_id) do
        Repo.update(Ybira.Folder.changeset(folder, %{parent_id: new_parent_id}))
      end
    end)
  end

  @impl true
  def delete_folder(%Scope{} = scope, public_id) when is_binary(public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, folder} <- fetch_folder(scope, public_id) do
        soft_delete_tree(folder.id)
        {:ok, :deleted}
      end
    end)
  end

  @impl true
  def publicar_folder(%Scope{} = scope, public_id) when is_binary(public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, folder} <- fetch_folder(scope, public_id) do
        Repo.update(Ybira.Folder.zona_changeset(folder, :praca))
      end
    end)
  end

  @impl true
  def tirar_folder_da_praca(%Scope{} = scope, public_id) when is_binary(public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, folder} <- fetch_folder(scope, public_id) do
        Repo.update(Ybira.Folder.zona_changeset(folder, :casa))
      end
    end)
  end

  @impl true
  def list_folder_contents(%Scope{} = scope, folder_public_id \\ nil, opts \\ []) do
    sort = normalize_sort(Keyword.get(opts, :sort))
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)

    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with {:ok, folder_id} <- resolve_folder_id(folder_public_id) do
        readable_folders = Maraca.readable_dynamic(scope.ava, "ybira_folder")
        readable_files = Maraca.readable_dynamic(scope.ava, "ybira_file")

        folders =
          folder_id
          |> folders_in()
          |> where(^readable_folders)
          |> apply_folder_sort(sort)
          |> Repo.all()

        {files, next_cursor} =
          folder_id
          |> files_in()
          |> where(^readable_files)
          |> apply_file_sort(sort)
          |> paginate_offset(limit, offset)

        {:ok, %{folders: folders, files: files, next_cursor: next_cursor}}
      end
    end)
  end

  defp paginate_offset(query, limit, offset) do
    rows =
      query
      |> limit(^(limit + 1))
      |> offset(^offset)
      |> Repo.all()

    if length(rows) > limit, do: {Enum.take(rows, limit), offset + limit}, else: {rows, nil}
  end

  @impl true
  def list_folders(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      query =
        from d in Ybira.Folder,
          as: :readable,
          where: is_nil(d.deleted_at),
          where: ^Maraca.readable_dynamic(scope.ava, "ybira_folder"),
          order_by: [asc: d.name]

      {:ok, Repo.all(query)}
    end)
  end

  ## Cota / armazenamento

  @impl true
  def check_capacity(%Scope{} = scope, byte_size) do
    {:ok, result} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok, quota_check(scope.tekoa.id, byte_size)}
      end)

    result
  end

  @impl true
  def storage_stats(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      tekoa = Repo.get!(Tekoa, scope.tekoa.id)
      {:ok, %{used_bytes: tekoa.storage_used_bytes, quota_bytes: tekoa.storage_quota_bytes}}
    end)
  end

  @impl true
  def list_recent(%Scope{} = scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, 4)

    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      files =
        Repo.all(
          from f in Ybira.File,
            as: :readable,
            where: is_nil(f.deleted_at),
            where: ^Maraca.readable_dynamic(scope.ava, "ybira_file"),
            order_by: [desc: f.id],
            limit: ^limit
        )

      {:ok, files}
    end)
  end

  @impl true
  def count_files(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      {:ok, Repo.aggregate(from(f in Ybira.File, where: is_nil(f.deleted_at)), :count)}
    end)
  end

  @impl true
  def count_photos(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      count =
        Repo.aggregate(
          from(f in Ybira.File,
            where: is_nil(f.deleted_at) and like(f.mime_type, "image/%")
          ),
          :count
        )

      {:ok, count}
    end)
  end

  @impl true
  def storage_stats_by_kind(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      rows =
        Repo.all(
          from f in Ybira.File,
            where: is_nil(f.deleted_at),
            group_by: fragment("split_part(?, '/', 1)", f.mime_type),
            select: {fragment("split_part(?, '/', 1)", f.mime_type), sum(f.file_size_bytes)}
        )

      {:ok, classify_storage_kinds(rows)}
    end)
  end

  # Categorias da tela de armazenamento: o prefixo do MIME decide; tudo que
  # não é mídia (application/*, text/*) conta como documento.
  defp classify_storage_kinds(rows) do
    Enum.reduce(rows, %{photos: 0, videos: 0, documents: 0, others: 0}, fn {prefix, bytes}, acc ->
      key =
        case prefix do
          "image" -> :photos
          "video" -> :videos
          "application" -> :documents
          "text" -> :documents
          _other -> :others
        end

      Map.update!(acc, key, &(&1 + to_integer(bytes)))
    end)
  end

  # `sum/1` sobre bigint volta como `Decimal` no Postgres; normalizamos para
  # inteiro (bytes são sempre inteiros) antes de somar no acumulador.
  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = bytes), do: Decimal.to_integer(bytes)
  defp to_integer(bytes) when is_integer(bytes), do: bytes

  @impl true
  def purge_deleted_files(%DateTime{} = cutoff) do
    files =
      Repo.all(
        from(f in Ybira.File, where: not is_nil(f.deleted_at) and f.deleted_at < ^cutoff),
        skip_tekoa_id: true
      )

    Enum.each(files, fn file ->
      {:ok, _} =
        Repo.transaction(fn ->
          Repo.delete!(file)
          adjust_storage_used(file.tekoa_id, -file.file_size_bytes, skip_tekoa_id: true)
        end)

      # Fora da transação: se o disco falhar, o registro já foi (sem órfão no
      # banco). Pior caso é um arquivo solto no disco, não inconsistência, mas
      # logamos para dar visibilidade a problemas recorrentes de disco.
      with {:error, reason} <- Elixir.File.rm(file.filepath) do
        Logger.warning("PurgeTrash: falha ao remover arquivo do disco",
          path: file.filepath,
          file_id: file.id,
          reason: reason
        )
      end
    end)

    # Pastas na lixeira só guardam metadados (sem bytes nem cota), apaga em lote.
    # `delete_folder/2` faz soft delete em cascata; sem isto, os registros de
    # pasta ficariam para sempre com `deleted_at` preenchido.
    Repo.delete_all(
      from(d in Ybira.Folder, where: not is_nil(d.deleted_at) and d.deleted_at < ^cutoff),
      skip_tekoa_id: true
    )

    {:ok, length(files)}
  end

  ## --- Helpers internos ---

  defp quota_check(tekoa_id, byte_size) do
    tekoa = Repo.get!(Tekoa, tekoa_id)

    cond do
      is_nil(tekoa.storage_quota_bytes) -> :ok
      tekoa.storage_used_bytes + byte_size <= tekoa.storage_quota_bytes -> :ok
      true -> {:error, :storage_quota_exceeded}
    end
  end

  defp adjust_storage_used(tekoa_id, delta, opts \\ []) do
    Repo.update_all(
      from(t in Tekoa, where: t.id == ^tekoa_id),
      [inc: [storage_used_bytes: delta]],
      opts
    )
  end

  defp copy_to_storage(%Scope{} = scope, tmp_path, original_filename) do
    today = Date.utc_today()

    dir =
      Path.join([
        storage_root(),
        scope.tekoa.public_id,
        "files",
        Integer.to_string(today.year),
        String.pad_leading(Integer.to_string(today.month), 2, "0")
      ])

    dest = Path.join(dir, Nanoid.generate(12) <> Path.extname(original_filename))

    with :ok <- Elixir.File.mkdir_p(dir),
         :ok <- Elixir.File.cp(tmp_path, dest) do
      {:ok, dest}
    end
  end

  defp hash_file(path) do
    hash =
      path
      |> Elixir.File.stream!(@hash_chunk_bytes)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, hash}
  rescue
    e in Elixir.File.Error -> {:error, e.reason}
  end

  defp storage_root, do: Application.fetch_env!(:taina, :storage_root)

  # --- Pastas (resolução, autorização, cascata) ---

  defp folder_by_public_id(public_id) do
    from d in Ybira.Folder, where: d.public_id == ^public_id and is_nil(d.deleted_at)
  end

  defp resolve_folder_id(nil), do: {:ok, nil}

  defp resolve_folder_id(public_id) when is_binary(public_id) do
    case Repo.one(folder_by_public_id(public_id)) do
      nil -> {:error, :not_found}
      folder -> {:ok, folder.id}
    end
  end

  defp fetch_folder(scope, public_id) do
    case Repo.one(folder_by_public_id(public_id)) do
      nil ->
        {:error, :not_found}

      folder ->
        if owner?(scope, folder.ava_id), do: {:ok, folder}, else: {:error, :not_found}
    end
  end

  defp fetch_owned_file(scope, public_id) do
    query = from f in Ybira.File, where: f.public_id == ^public_id and is_nil(f.deleted_at)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      file -> if owner?(scope, file.ava_id), do: {:ok, file}, else: {:error, :not_found}
    end
  end

  # Só o dono muta seus recursos. O zelador não tem acesso automático (RFC 003:
  # "zero autoridade sobre dados, sem atalho para a casa de ninguém"), quando
  # precisar, pede via `Maraca.request_access/5` e o dono aprova.
  defp owner?(%Scope{ava: %Ava{id: id}}, owner_id), do: id == owner_id

  # Regra de leitura das duas zonas (RFC_003 D2) para um recurso ja carregado:
  # praca OU dono OU permissao explicita. Devolve {:error, :forbidden} para casa
  # nao autorizada, distinto de :not_found.
  defp authorize_read(%Scope{} = scope, resource_type, resource) do
    if Maraca.can_read?(scope.ava, resource.zona, resource.ava_id, resource_type, resource.public_id) do
      {:ok, resource}
    else
      {:error, :forbidden}
    end
  end

  # Mover `folder_id` para baixo de `new_parent_id` fecharia um ciclo se
  # `folder_id` for o próprio `new_parent_id` ou um ancestral dele.
  defp ensure_acyclic(_folder_id, nil), do: :ok

  defp ensure_acyclic(folder_id, new_parent_id) do
    if ancestor_or_self?(new_parent_id, folder_id),
      do: {:error, :circular_reference},
      else: :ok
  end

  # Uma única CTE recursiva sobe a cadeia de ancestrais de `start_id` (incluindo
  # ele) e responde se `folder_id` aparece lá, sem N+1 nem recursão Elixir
  # ilimitada. Roda sob `with_tekoa`, então o RLS filtra por Tekoa.
  defp ancestor_or_self?(start_id, folder_id) do
    {:ok, %{rows: [[count]]}} =
      Repo.query(
        """
        WITH RECURSIVE ancestors AS (
          SELECT id, parent_id FROM ybira.folders WHERE id = $1
          UNION ALL
          SELECT f.id, f.parent_id FROM ybira.folders f
          JOIN ancestors a ON f.id = a.parent_id
        )
        SELECT count(*) FROM ancestors WHERE id = $2
        """,
        [start_id, folder_id]
      )

    count > 0
  end

  # Soft delete em cascata sem recursão Elixir: uma CTE coleta a subárvore (raiz
  # + descendentes não-deletados) e dois `update_all` marcam arquivos e pastas.
  defp soft_delete_tree(root_id) do
    now = DateTime.utc_now()
    folder_ids = descendant_folder_ids(root_id)

    Repo.update_all(
      from(f in Ybira.File, where: f.folder_id in ^folder_ids and is_nil(f.deleted_at)),
      set: [deleted_at: now]
    )

    Repo.update_all(
      from(d in Ybira.Folder, where: d.id in ^folder_ids and is_nil(d.deleted_at)),
      set: [deleted_at: now]
    )

    :ok
  end

  defp descendant_folder_ids(root_id) do
    {:ok, %{rows: rows}} =
      Repo.query(
        """
        WITH RECURSIVE subtree AS (
          SELECT id FROM ybira.folders WHERE id = $1
          UNION ALL
          SELECT f.id FROM ybira.folders f
          JOIN subtree s ON f.parent_id = s.id
          WHERE f.deleted_at IS NULL
        )
        SELECT id FROM subtree
        """,
        [root_id]
      )

    List.flatten(rows)
  end

  # Conteúdo da pasta (sem ordenação, quem chama aplica `apply_*_sort`).
  defp folders_in(nil), do: from(d in Ybira.Folder, as: :readable, where: is_nil(d.parent_id) and is_nil(d.deleted_at))

  defp folders_in(folder_id),
    do: from(d in Ybira.Folder, as: :readable, where: d.parent_id == ^folder_id and is_nil(d.deleted_at))

  defp files_in(nil), do: from(f in Ybira.File, as: :readable, where: is_nil(f.folder_id) and is_nil(f.deleted_at))

  defp files_in(folder_id),
    do: from(f in Ybira.File, as: :readable, where: f.folder_id == ^folder_id and is_nil(f.deleted_at))

  # Ordenação dinâmica (nome/data/tamanho x asc/desc), com `id` como desempate
  # estável. A paginação aqui é por offset (não keyset), o que permite qualquer
  # ordem sem cursor composto, suficiente para uma caixa de comunidade.
  @sort_fields ~w(name date size)a
  @sort_dirs ~w(asc desc)a

  defp normalize_sort({field, dir}) when field in @sort_fields and dir in @sort_dirs, do: {field, dir}
  defp normalize_sort(_other), do: {:date, :desc}

  defp apply_file_sort(query, {:name, dir}), do: order_by(query, [f], [{^dir, f.original_filename}, {^dir, f.id}])
  defp apply_file_sort(query, {:size, dir}), do: order_by(query, [f], [{^dir, f.file_size_bytes}, {^dir, f.id}])
  defp apply_file_sort(query, {:date, dir}), do: order_by(query, [f], [{^dir, f.inserted_at}, {^dir, f.id}])

  defp apply_folder_sort(query, {:name, dir}), do: order_by(query, [d], [{^dir, d.name}])
  defp apply_folder_sort(query, {:date, dir}), do: order_by(query, [d], [{^dir, d.inserted_at}])
  # Pastas não têm tamanho; ao ordenar por tamanho, mantêm ordem alfabética.
  defp apply_folder_sort(query, {:size, _dir}), do: order_by(query, [d], asc: d.name)

  defp fetch_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  # --- Paginação por keyset ---

  defp fetch_page(query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    cursor = Keyword.get(opts, :after_cursor)

    rows =
      query
      |> apply_cursor(cursor)
      |> limit(^(limit + 1))
      |> Repo.all()

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      {page, encode_cursor(List.last(page))}
    else
      {rows, nil}
    end
  end

  defp apply_cursor(query, nil), do: query

  defp apply_cursor(query, cursor) when is_binary(cursor) do
    case decode_cursor(cursor) do
      {:ok, id} -> where(query, [x], x.id < ^id)
      :error -> query
    end
  end

  defp encode_cursor(%{id: id}), do: Base.url_encode64(<<id::64>>, padding: false)

  defp decode_cursor(cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, <<id::64>>} -> {:ok, id}
      _ -> :error
    end
  end
end
