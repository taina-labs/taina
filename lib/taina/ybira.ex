defmodule Taina.Ybira do
  @moduledoc """
  O Ybira do produto, sobre o kernel Ypy.

  Os verbos de armazenamento (upload, leitura, lixeira, zonas, mover,
  renomear) sao do kernel (`Ypy.Ybira`): cada mutacao anexa uma entrada
  assinada a cadeia unica e os bytes moram no `Taina.Blobs` enderecados por
  CID. Aqui fica o que e da caixa: as renditions de imagem (Oban), a
  navegacao por pastas (breadcrumb, conteudo combinado), os agregados do
  painel e o expurgo da lixeira.

  Deletar um arquivo ou pasta só preenche `apagado_em`, os bytes ficam no
  disco e a cota não é devolvida na hora. O worker `Taina.Ybira.Workers.PurgeTrash`
  apaga de vez o que está na lixeira há mais de 30 dias e só então recupera a
  cota. Até lá, `restore_file/2` traz o arquivo de volta (solto na raiz quando
  a pasta dele também foi apagada) e `restore_folder/2` traz a pasta inteira,
  com o que foi apagado junto dela.


  Os bytes do expurgo não saem na hora: os CIDs vão para a fila do GC
  diferido (`Taina.Ybira.BlobGc`) e o worker `Taina.Ybira.Workers.BlobGc`,
  de hora em hora, apaga do disco só o CID que nenhuma linha referencia mais.
  Duas cercas guardam a corrida com a dedup. A travessa local
  (`Taina.Ybira.BlobLock`) faz a conferência de referências e o apagão do GC
  se excluírem da gravação dos bytes no upload: o mesmo CID nunca anda nos
  dois lados ao mesmo tempo, e só espera a vez quem sobe os MESMOS bytes. A
  graça de uma hora é a cerca de trás: cobre a janela entre o enfileiramento
  do CID e a rodada do GC, em que um upload concorrente pode reanimar o blob
  (e a fila só registra o pleno).

  Listagens usam cursor por rkey (TID, ordenável por tempo): o cursor é o
  próprio rkey do último item; passe-o de volta em `:after_cursor` para a
  próxima página.

  """

  import Ecto.Query

  alias Taina.Blobs
  alias Taina.Jaci.Photo
  alias Taina.Keys
  alias Taina.Repo
  alias Taina.Ybira.BlobGc
  alias Taina.Ybira.BlobLock
  alias Taina.Ybira.MimeDetector
  alias Taina.Ybira.Workers.Rendition
  alias Ypy.BlobStore.Disk
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Policy
  alias Ypy.Maraca.Store
  alias Ypy.Maraca.Tekoa
  alias Ypy.Scope
  alias Ypy.Ybira, as: Kernel
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder
  alias Ypy.Ybira.Queries, as: KernelQueries
  alias Ypy.Ybira.Store, as: KernelStore

  require Logger

  @default_limit 50
  @tipo_file "ypy.file.v0"
  @tipo_folder "ypy.folder.v0"
  @chunk_bytes 65_536
  @folder_path_max_depth 32

  @type datetime :: DateTime.t()
  @type file :: File.t()
  @type id :: integer()
  @type metadata :: map()
  @type path :: Path.t()
  @type scope :: Scope.t()
  @type text :: String.t()

  @doc "O caminho no disco dos bytes do arquivo (endereçados pelo CID do blob)."
  @spec blob_path(file()) :: {:ok, path()} | {:error, :not_found}
  def blob_path(%File{} = file) do
    case Disk.open(Blobs.new(), Ypy.Cid.parse(file.blob_cid)) do
      {:ok, path} -> {:ok, path}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  @doc "Alguma linha de arquivo referencia o CID? (a mesma conferência do expurgo, agora no GC)."
  @spec blob_referenced?(text()) :: boolean()
  def blob_referenced?(blob_cid) when is_binary(blob_cid) do
    Repo.exists?(from(f in File, where: f.blob_cid == ^blob_cid), skip_tekoa_id: true)
  end

  @doc "Cabe `byte_size` na cota da Tekoa? (o upload do kernel cobra de novo)."
  def check_capacity(%Scope{} = scope, byte_size) do
    within_tekoa(scope, fn ->
      {:ok, quota_check(scope.tekoa.id, byte_size)}
    end)
  end

  def count_files(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      {:ok, Repo.aggregate(readable_files_query(scope), :count)}
    end)
  end

  def count_photos(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      count =
        scope
        |> readable_files_query()
        |> where([f], like(f.mime, "image/%"))
        |> Repo.aggregate(:count)

      {:ok, count}
    end)
  end

  @doc """
  Cria a pasta (kernel: `Ypy.Ybira.criar_pasta/4`), sempre na casa; a praca
  e um ato proprio (`publicar_folder/2`), nunca uma escolha na criacao.
  """
  def create_folder(%Scope{} = scope, %{} = attrs) do
    within_tekoa(scope, fn ->
      Kernel.criar_pasta(Repo, Keys.new(), scope, fetch_attr(attrs, :name), parent: fetch_attr(attrs, :parent_rkey))
    end)
  end

  @doc "Manda o arquivo para a lixeira (kernel: `Ypy.Ybira.apagar/5`)."
  def delete_file(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.apagar(Repo, Keys.new(), scope, @tipo_file, rkey) end)
  end

  @doc "Apaga a pasta da lixeira e toda a subarvore dela."
  def delete_folder(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn ->
      with {:ok, folder} <- fetch_owned_folder(scope, rkey),
           :ok <- soft_delete_tree(scope.tekoa.id, folder.id) do
        {:ok, :deleted}
      end
    end)
  end

  @doc """
  O `public_id` do dono de vários recursos, em UMA consulta sobre
  `Ypy.Maraca.Ava` (o serializer da API): mapa `dono_id => public_id`. Sem
  entrada para id nulo (arquivo/pasta órfão, caso defensivo do FK).
  """
  @spec donos_public_ids(scope(), [id()]) :: {:ok, %{id() => text()}}
  def donos_public_ids(%Scope{} = scope, dono_ids) when is_list(dono_ids) do
    within_tekoa(scope, fn ->
      ids = dono_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

      donos = Repo.all(from(a in Ava, where: a.id in ^ids, select: {a.id, a.public_id}))

      {:ok, Map.new(donos)}
    end)
  end

  @doc """
  Enfileira CIDs de blobs expurgados para o GC diferido (`Taina.Ybira.BlobGc`).
  Idempotente: CID que já está na fila fica com o `enqueued_at` de origem,
  para não re-envelhecer (a graça de uma hora conta do primeiro expurgo).
  """
  @spec enqueue_blob_gc([text()]) :: {:ok, non_neg_integer()}
  def enqueue_blob_gc(blob_cids) when is_list(blob_cids) do
    agora = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.insert_all(
        BlobGc,
        blob_cids |> Enum.uniq() |> Enum.map(&%{blob_cid: &1, enqueued_at: agora}),
        on_conflict: :nothing,
        conflict_target: :blob_cid,
        skip_tekoa_id: true
      )

    {:ok, count}
  end

  @doc """
  O alvo de um pedido de acesso: o dono resolvido (para o PubSub e a frase da
  tela) quando quem pergunta ainda nao le o arquivo; quem ja le recebe
  {:error, :already_readable}.
  """
  def fetch_access_target(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> access_target(scope, rkey) end)
  end

  @doc """
  Pasta que contém um arquivo, pelo rkey dela, quando visível para quem
  pergunta. Serve para o botão de voltar da tela do arquivo: ele devolve para
  a pasta onde o arquivo mora, não para o início. `{:error, :no_folder}` para
  arquivo solto na raiz; `{:error, :not_found}` quando a pasta já está na
  lixeira; `{:error, :forbidden}` para a casa de outra pessoa.
  """
  @spec file_folder_rkey(scope(), file()) ::
          {:ok, text()} | {:error, :no_folder | :not_found | :forbidden}
  def file_folder_rkey(_scope, %File{folder_id: nil}), do: {:error, :no_folder}

  def file_folder_rkey(%Scope{} = scope, %File{folder_id: folder_id}) when is_integer(folder_id) do
    within_tekoa(scope, fn -> folder_rkey_visivel(scope, folder_id) end)
  end

  @doc """
  A pasta pai de vários arquivos, resolvida pela regra de leitura em lote (o
  `file_folder_rkey/2` de página): mapa `file_id => rkey` da pasta, e `nil`
  para arquivo solto, pasta na lixeira ou casa não-legível -- os mesmos
  nulos do unitário. As pastas distintas da página saem em uma consulta; a
  regra de leitura (as concessões) carrega uma vez só.
  """
  @spec files_folder_rkeys(scope(), [file()]) :: {:ok, %{id() => nil | text()}}
  def files_folder_rkeys(%Scope{} = scope, files) when is_list(files) do
    within_tekoa(scope, fn ->
      folder_ids = files |> Enum.map(& &1.folder_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      # As concessões do leitor: uma consulta para a página inteira.
      concessoes = Store.concessoes_ativas(Repo, scope.tekoa.id, scope.ava.id)

      readable_rkeys = readable_folder_rkeys(scope, folder_ids, concessoes)

      {:ok,
       Map.new(files, fn %File{id: id, folder_id: folder_id} ->
         {id, Map.get(readable_rkeys, folder_id, nil)}
       end)}
    end)
  end

  @doc """
  Quantos itens cada pasta da listagem tem, para o meta "Pasta, 4 itens" do
  board: subpastas mais arquivos, sem a lixeira, na mesma regra de leitura da
  própria pasta. Uma consulta por tipo, agrupada por pasta, a listagem não vira N+1.

  Devolve `%{folder_id => count}`; pasta sem filho aparece com 0.
  """
  def folder_item_counts(%Scope{} = scope, folder_ids) when is_list(folder_ids) do
    ids = folder_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      {:ok, %{}}
    else
      within_tekoa(scope, fn -> {:ok, sum_counts(scope, ids)} end)
    end
  end

  @doc """
  Cadeia de pastas de uma pasta até a raiz (raiz -> atual, inclusive), na ordem
  do breadcrumb. Cada elo é `%{rkey: rkey, nome: nome}`; quem pergunta só recebe
  a cadeia até a última pasta que pode ler.
  """
  @spec folder_path(scope(), text()) :: {:ok, [%{rkey: text(), nome: text()}]} | {:error, :not_found}
  def folder_path(%Scope{} = scope, folder_rkey) when is_binary(folder_rkey) do
    within_tekoa(scope, fn ->
      with {:ok, rows} <- folder_chain(folder_rkey) do
        {:ok, readable_chain(scope, rows)}
      end
    end)
  end

  @doc """
  Uma rodada do GC diferido: para cada fila enfileirada antes do `cutoff` (a
  graça de uma hora fecha a janela entre o enfileiramento e a rodada), apaga
  os bytes do disco quando nenhuma linha de `ybira_files` referencia o CID;
  quando o blob voltou a viver (o upload concorrente que o compartilhou
  commitou), só a fila cai. Devolve o placar `deleted`/`kept`.
  """
  @spec gc_blobs(datetime()) :: {:ok, %{deleted: non_neg_integer(), kept: non_neg_integer()}}
  def gc_blobs(%DateTime{} = cutoff) do
    rows = Repo.all(from(g in BlobGc, where: g.enqueued_at < ^cutoff), skip_tekoa_id: true)

    placar =
      rows
      |> Enum.map(&gc_blob_row/1)
      |> Enum.frequencies()

    {:ok, %{deleted: Map.get(placar, :deleted, 0), kept: Map.get(placar, :kept, 0)}}
  end

  @doc """
  O arquivo pelo rkey, sob a regra de leitura: casa alheia sem concessao
  responde {:error, :forbidden}, rkey inexistente responde {:error, :not_found}.
  """
  def get_file(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.get_file(Repo, scope, rkey) end)
  end

  def get_folder(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.get_folder(Repo, scope, rkey) end)
  end

  @doc "O arquivo apagado do proprio morador, para o preview da lixeira."
  def get_trashed_file(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> trashed_file(scope, rkey) end)
  end

  @doc """
  Os arquivos legíveis pela regra (praca OU dono OU concessao), do mais
  recente para o mais antigo, dentro da pasta dada (ou soltos na raiz).
  """
  def list_files(%Scope{} = scope, folder_rkey \\ nil, opts \\ []) do
    within_tekoa(scope, fn ->
      {:ok, page(files_query(scope, folder_rkey), opts)}
    end)
  end

  @doc """
  O conteudo combinado de uma pasta (pastas e arquivos legiveis, com a
  ordenacao da tela). Composto sobre as queries do kernel, que ja trazem a
  regra de leitura no nivel do SQL.
  """
  def list_folder_contents(%Scope{} = scope, folder_rkey \\ nil, opts \\ []) do
    sort = normalize_sort(Keyword.get(opts, :sort))
    limit = Keyword.get(opts, :limit, @default_limit)
    offset = Keyword.get(opts, :offset, 0)
    zona = Keyword.get(opts, :zona)

    within_tekoa(scope, fn ->
      with {:ok, folder} <- resolve_folder(scope, folder_rkey) do
        folders =
          scope
          |> folders_query(folder && folder.id)
          |> maybe_filter_zone(root_listing_zone(folder, zona))
          |> apply_folder_sort(sort)
          # Folder owners are resolved through the existing batched serializer lookup.
          # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
          |> Repo.all()

        {files, next_cursor} =
          scope
          |> files_query(folder)
          |> maybe_filter_zone(root_listing_zone(folder, zona))
          |> apply_file_sort(sort)
          |> paginate_offset(limit, offset)

        {:ok, %{folders: folders, files: files, next_cursor: next_cursor}}
      end
    end)
  end

  @doc "As pastas legiveis (drop-down de destino, navegacao)."
  def list_folders(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      {:ok, Kernel.list_folders(Repo, scope, [])}
    end)
  end

  @doc "Os arquivos mais recentes legiveis (home)."
  def list_recent(%Scope{} = scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, 4)

    within_tekoa(scope, fn ->
      files =
        scope
        |> readable_files_query()
        |> order_by([f], desc: f.rkey)
        |> limit(^limit)
        # File associations are resolved through existing batched lookups.
        # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
        |> Repo.all()

      {:ok, files}
    end)
  end

  @doc "A lixeira do próprio morador (só o dono vê o lixo dele, nem o kernel lista)."
  def list_trash(%Scope{} = scope, opts \\ []) do
    within_tekoa(scope, fn ->
      query =
        from(f in File,
          where: f.tekoa_id == ^scope.tekoa.id and f.dono_id == ^scope.ava.id and not is_nil(f.apagado_em),
          order_by: [desc: f.rkey]
        )

      {:ok, page(query, opts)}
    end)
  end

  @doc "As pastas na lixeira do próprio morador (mesma regra dos arquivos)."
  def list_trash_folders(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      folders =
        Repo.all(
          from(p in Folder,
            where: p.tekoa_id == ^scope.tekoa.id and p.dono_id == ^scope.ava.id and not is_nil(p.apagado_em),
            order_by: [desc: p.rkey]
          )
        )

      {:ok, folders}
    end)
  end

  @doc "O limite configurado por arquivo, em bytes."
  @spec max_blob_size() :: pos_integer()
  def max_blob_size, do: Taina.Config.max_blob_size()

  @doc "Move para a pasta de rkey dado (ou nil, para solto; kernel: `Ypy.Ybira.mover/5`)."
  def move_file(%Scope{} = scope, rkey, folder_rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.mover(Repo, Keys.new(), scope, rkey, folder_rkey) end)
  end

  @doc """
  Mover pasta e da caixa (o kernel move so arquivo, RFC_006 secao 9): guarda
  de dono, destino dono e o grafo sem ciclos ficam aqui. Nota: a mudanca de
  pai nao anexa entrada na cadeia (o verbo nao existe no kernel ainda).
  """
  def move_folder(%Scope{} = scope, rkey, new_parent_rkey) when is_binary(rkey) do
    within_tekoa(scope, fn ->
      with {:ok, folder} <- fetch_owned_folder(scope, rkey),
           {:ok, new_parent_id} <- resolve_owned_folder_id(scope, new_parent_rkey),
           :ok <- ensure_acyclic(folder.id, new_parent_id) do
        Repo.update(Folder.changeset(folder, %{parent_id: new_parent_id}))
      end
    end)
  end

  def pending_job_counts do
    %{
      renditions: count_pending_jobs("Taina.Ybira.Workers.Rendition"),
      trash_purge: count_pending_jobs("Taina.Ybira.Workers.PurgeTrash")
    }
  end

  @doc """
  Os metadados de rendição do arquivo (dimensões, EXIF, thumbnails): gravados
  pelo worker no expurgo, se o job ainda não rodou, mapa vazio.
  """
  @spec photo_metadata(scope(), file()) :: {:ok, metadata()}
  def photo_metadata(%Scope{} = scope, %File{} = file) do
    within_tekoa(scope, fn ->
      {:ok, photo_metadata!(file.id)}
    end)
  end

  @doc """
  Os metadados de vários arquivos, em UMA consulta (o lote do serializer da
  API): mapa `file_id => metadata`, sem entrada para quem ainda não tem linha
  de foto (o worker não rodou).
  """
  @spec photos_metadata(scope(), [id()]) :: {:ok, %{id() => metadata()}}
  def photos_metadata(%Scope{} = scope, file_ids) when is_list(file_ids) do
    within_tekoa(scope, fn ->
      photos = Repo.all(from(p in Photo, where: p.file_id in ^file_ids))
      {:ok, Map.new(photos, fn p -> {p.file_id, p.metadata || %{}} end)}
    end)
  end

  @doc "Nomes legiveis na praca para recursos citados por uma pagina do mural."
  def public_resource_names(%Scope{} = scope, resources) when is_list(resources) do
    file_rkeys = resource_rkeys(resources, @tipo_file)
    folder_rkeys = resource_rkeys(resources, @tipo_folder)

    within_tekoa(scope, fn ->
      file_names =
        if file_rkeys == [] do
          []
        else
          Repo.all(
            from(f in File,
              where:
                f.tekoa_id == ^scope.tekoa.id and f.rkey in ^file_rkeys and f.zona == :praca and
                  is_nil(f.apagado_em),
              select: {{@tipo_file, f.rkey}, f.nome}
            )
          )
        end

      folder_names =
        if folder_rkeys == [] do
          []
        else
          Repo.all(
            from(f in Folder,
              where:
                f.tekoa_id == ^scope.tekoa.id and f.rkey in ^folder_rkeys and f.zona == :praca and
                  is_nil(f.apagado_em),
              select: {{@tipo_folder, f.rkey}, f.nome}
            )
          )
        end

      {:ok, Map.new(file_names ++ folder_names)}
    end)
  end

  @doc "Publica na praca (kernel: `Ypy.Ybira.publicar/5`)."
  def publicar_file(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.publicar(Repo, Keys.new(), scope, @tipo_file, rkey) end)
  end

  def publicar_folder(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> change_folder_tree_zone(scope, rkey, :publicar) end)
  end

  @doc """
  Expurga a lixeira: apaga de vez arquivos e pastas com `apagado_em` anterior
  ao cutoff, devolve a cota e enfileira os CIDs dos bytes para o GC diferido
  (o worker `Taina.Ybira.Workers.BlobGc` tira do disco, uma hora depois, o
  CID que nenhuma linha referencia mais). Job de sistema, cruza todas as
  Tekoas.
  """
  def purge_deleted_files(%DateTime{} = cutoff) do
    # Job de sistema que cruza todas as Tekoas: sem contexto, as queries
    # declaram `skip_tekoa_id: true`. Blobs originais ficam para o GC diferido;
    # thumbnails das imagens purgadas sao removidas junto com os registros.
    with {:ok, files} <- Repo.with_system(fn -> purge_deleted_files_in_system(cutoff) end) do
      {:ok, length(files)}
    end
  end

  @doc "Apaga de vez um arquivo da lixeira do proprio morador."
  def purge_trash_file(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn ->
      with {:ok, file} <- fetch_trashed_owned_file(scope, rkey),
           {:ok, 1} <- purge_files(scope.tekoa.id, [file]) do
        {:ok, file}
      end
    end)
  end

  @doc "Apaga de vez uma pasta da lixeira e toda a subarvore dela."
  def purge_trash_folder(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn ->
      with {:ok, folder} <- fetch_trashed_owned_folder(scope, rkey),
           {:ok, folder_ids} <- owned_subtree_folder_ids(scope, folder.id),
           {:ok, files} <- trashed_subtree_files(scope, folder_ids),
           {:ok, _folders} <- trashed_subtree_folders(scope, folder_ids),
           {:ok, _file_count} <- purge_files(scope.tekoa.id, files),
           {:ok, folder_count} <- purge_folders(scope.tekoa.id, folder_ids) do
        {:ok, %{folder: folder, folders: folder_count, files: length(files)}}
      end
    end)
  end

  @doc "Renomeia (o nome do record, nao os bytes; kernel: `Ypy.Ybira.renomear/6`)."
  def rename_file(%Scope{} = scope, rkey, new_name) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.renomear(Repo, Keys.new(), scope, @tipo_file, rkey, new_name) end)
  end

  def rename_folder(%Scope{} = scope, rkey, new_name) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.renomear(Repo, Keys.new(), scope, @tipo_folder, rkey, new_name) end)
  end

  @doc """
  Tira da lixeira (kernel: `Ypy.Ybira.restaurar/5`). Se a pasta-pai do
  arquivo também estiver na lixeira (ou já tiver sido expurgada), o arquivo
  volta solto na raiz: com o `folder_id` apontando para pasta apagada, ele
  não apareceria em listagem nenhuma.
  """
  def restore_file(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn ->
      with {:ok, file} <- Kernel.restaurar(Repo, Keys.new(), scope, @tipo_file, rkey) do
        restore_to_root_if_orphaned(scope, file)
      end
    end)
  end

  @doc """
  Restaura a pasta como unidade: ela e tudo o que foi apagado junto com ela
  (a subárvore com o mesmo `apagado_em`) volta. Se a pasta-pai dela também
  estiver na lixeira, a pasta volta solta na raiz. Só a dona restaura.
  """
  def restore_folder(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn ->
      with {:ok, folder} <- fetch_trashed_owned_folder(scope, rkey) do
        restore_folder_subtree(scope, folder)
      end
    end)
  end

  def storage_stats(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      tekoa = Repo.get!(Tekoa, scope.tekoa.id)
      {:ok, %{used_bytes: tekoa.storage_used_bytes, quota_bytes: tekoa.storage_quota_bytes}}
    end)
  end

  defp access_target(%Scope{} = scope, rkey) do
    case KernelStore.get_file(Repo, scope.tekoa.id, rkey) do
      nil -> {:error, :not_found}
      file -> access_target_readable(scope, rkey, file)
    end
  end

  defp access_target_readable(%Scope{} = scope, rkey, file) do
    if Kernel.readable?(Repo, scope, @tipo_file, rkey) do
      {:error, :already_readable}
    else
      # O PubSub do pedido usa o topico do dono, que precisa da Tekoa
      # para o `for_ava`; o preload cobre.
      owner = Repo.preload(file, dono: :tekoa).dono
      {:ok, %{owner: owner, rkey: rkey, nome: file.nome}}
    end
  end

  # Soma por Tekoa dos bytes dos arquivos apagados: um ajuste de cota por
  # comunidade, não um por arquivo.
  defp adjust_storage_used(tekoa_id, delta) do
    Repo.update_all(
      from(t in Tekoa, where: t.id == ^tekoa_id),
      [inc: [storage_used_bytes: delta]],
      skip_tekoa_id: true
    )
  end

  defp blob_cid(path) do
    case Elixir.File.open(path, [:read, :binary]) do
      {:ok, dev} ->
        try do
          {:ok, cid_of_stream(dev, :crypto.hash_init(:sha256))}
        after
          :file.close(dev)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp blob_size_allowed?(size) do
    if size <= max_blob_size(), do: :ok, else: {:error, :blob_too_large}
  end

  defp bytes_per_tekoa(files) do
    files
    |> Enum.group_by(& &1.tekoa_id)
    |> Enum.map(fn {tekoa_id, trashed} ->
      {tekoa_id, trashed |> Enum.map(& &1.tamanho) |> Enum.sum()}
    end)
  end

  ## Helpers internos

  # Ajuste de cota de sistema (fora de contexto de Tekoa, job que cruza todas).
  defp change_folder_tree_zone(scope, rkey, action) do
    with {:ok, folder} <- change_zone(scope, @tipo_folder, rkey, action),
         {:ok, folder_rkeys, file_rkeys} <- folder_tree_items(scope, folder),
         :ok <- change_tree_items(scope, action, folder_rkeys, file_rkeys) do
      {:ok, folder}
    end
  end

  defp change_tree_items(scope, action, folder_rkeys, file_rkeys) do
    items = Enum.map(folder_rkeys, &{@tipo_folder, &1}) ++ Enum.map(file_rkeys, &{@tipo_file, &1})

    Enum.reduce_while(items, :ok, fn {kind, rkey}, :ok ->
      case change_zone(scope, kind, rkey, action) do
        {:ok, _item} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp change_zone(scope, kind, rkey, :publicar), do: Kernel.publicar(Repo, Keys.new(), scope, kind, rkey)

  defp change_zone(scope, kind, rkey, :tirar), do: Kernel.tirar_da_praca(Repo, Keys.new(), scope, kind, rkey)

  defp cid_of_stream(dev, hash) do
    case :file.read(dev, @chunk_bytes) do
      {:ok, chunk} -> cid_of_stream(dev, :crypto.hash_update(hash, chunk))
      :eof -> Ypy.Cid.from_digest(:crypto.hash_final(hash), Ypy.Cid.raw())
      {:error, reason} -> {:error, reason}
    end
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

  ## Jobs (saúde da caixa, painel)

  # Trabalho em espera ou em execução; `scheduled` é o cron no calendário, não
  # trabalho atrasado.
  @job_pending_states ~W(available executing retryable)

  # A fila do Oban é infraestrutura da caixa: tabela `oban_jobs`, isenta do
  # contexto de Tekoa em `Repo.prepare_query/3`.
  defp count_pending_jobs(worker) do
    Repo.aggregate(
      from(j in Oban.Job, where: j.worker == ^worker, where: j.state in ^@job_pending_states),
      :count
    )
  end

  defp counts_by(%Scope{} = scope, :folder, parent_ids) do
    scope
    |> folders_by_parent(parent_ids)
    |> group_by([p], p.parent_id)
    |> select([p], {p.parent_id, count(p.id)})
    # Aggregate tuple projection; there are no associations to preload.
    # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
    |> Repo.all()
    |> Map.new()
  end

  defp counts_by(%Scope{} = scope, :file, parent_ids) do
    scope
    |> base()
    |> where([f], f.folder_id in ^parent_ids)
    |> group_by([f], f.folder_id)
    |> select([f], {f.folder_id, count(f.id)})
    # Aggregate tuple projection; there are no associations to preload.
    # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
    |> Repo.all()
    |> Map.new()
  end

  defp delete_thumbnail_paths(paths) do
    Enum.reduce_while(Map.values(paths), :ok, fn path, :ok ->
      case Elixir.File.rm(path) do
        :ok -> {:cont, :ok}
        {:error, :enoent} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp delete_thumbnails(files, tekoa_public_ids) do
    files
    |> Enum.filter(&image?(&1.mime))
    |> Enum.reduce_while(:ok, fn file, :ok ->
      paths = Rendition.thumbnail_paths(Map.fetch!(tekoa_public_ids, file.tekoa_id), file.rkey)

      case delete_thumbnail_paths(paths) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp descendant_folder_ids(parent_id, folders) do
    folders
    |> Enum.filter(&(&1.parent_id == parent_id))
    |> Enum.flat_map(fn folder -> [folder.id | descendant_folder_ids(folder.id, folders)] end)
  end

  defp drop_blob_gc_row(%BlobGc{} = row), do: Repo.delete!(row, skip_tekoa_id: true)

  # A regra de leitura sobre cada pasta pai distinta da página: fora do mapa
  # (nil, como no `file_folder_rkey/2`) pasta expurgada ou casa não-legível.
  defp fetch_trashed_owned_file(%Scope{} = scope, rkey) do
    case KernelStore.get_file(Repo, scope.tekoa.id, rkey, true) do
      nil ->
        {:error, :not_found}

      %File{} = file ->
        cond do
          file.dono_id != scope.ava.id -> {:error, :not_found}
          is_nil(file.apagado_em) -> {:error, :invalid_status}
          true -> {:ok, file}
        end
    end
  end

  # A regra de leitura sobre cada pasta pai distinta da página: fora do mapa
  # (nil, como no `file_folder_rkey/2`) pasta expurgada ou casa não-legível.
  defp folder_chain(folder_rkey) do
    statement = """
    WITH RECURSIVE chain AS (
      SELECT f.id, f.parent_id, f.rkey, f.nome, f.dono_id, f.zona, 0 AS depth
      FROM ybira_folders f
      WHERE f.rkey = $1 AND f.apagado_em IS NULL
      UNION ALL
      SELECT p.id, p.parent_id, p.rkey, p.nome, p.dono_id, p.zona, c.depth + 1
      FROM ybira_folders p
      JOIN chain c ON p.id = c.parent_id AND c.depth < $2
      WHERE p.apagado_em IS NULL
    )
    SELECT rkey, nome, dono_id, zona FROM chain ORDER BY depth ASC
    """

    case Repo.query(statement, [folder_rkey, @folder_path_max_depth]) do
      {:ok, %{rows: rows}} ->
        rows
        |> Enum.map(fn [rkey, nome, dono_id, zona] ->
          %{rkey: rkey, nome: nome, dono_id: dono_id, zona: zona_atom(zona)}
        end)
        |> case do
          [] -> {:error, :not_found}
          rows -> {:ok, rows}
        end

      {:error, _reason} = error ->
        error
    end
  end

  # Pastas de uma pasta (ou da raiz), legiveis pela regra do kernel.
  defp folder_rkey_visivel(%Scope{} = scope, folder_id) do
    case Repo.one(from(p in Folder, where: p.id == ^folder_id and is_nil(p.apagado_em))) do
      nil -> {:error, :not_found}
      folder -> if readable?(scope, folder), do: {:ok, folder.rkey}, else: {:error, :forbidden}
    end
  end

  defp folder_tree_items(scope, root_folder) do
    folders =
      Repo.all(
        from(f in Folder,
          where: f.tekoa_id == ^scope.tekoa.id and f.dono_id == ^scope.ava.id and is_nil(f.apagado_em)
        )
      )

    descendant_ids = descendant_folder_ids(root_folder.id, folders)
    folders_by_id = Map.new(folders, &{&1.id, &1})
    folder_rkeys = Enum.map(descendant_ids, &Map.fetch!(folders_by_id, &1).rkey)
    folder_ids = [root_folder.id | descendant_ids]

    file_rkeys =
      Repo.all(
        from(f in File,
          where:
            f.tekoa_id == ^scope.tekoa.id and f.dono_id == ^scope.ava.id and f.folder_id in ^folder_ids and
              is_nil(f.apagado_em),
          select: f.rkey
        )
      )

    {:ok, folder_rkeys, file_rkeys}
  end

  # A regra de leitura sobre cada pasta pai distinta da página: fora do mapa
  # (nil, como no `file_folder_rkey/2`) pasta expurgada ou casa não-legível.
  defp folders_by_parent(%Scope{} = scope, parent_ids) do
    KernelQueries.readable_folder(
      from(p in Folder,
        where: p.tekoa_id == ^scope.tekoa.id and p.parent_id in ^parent_ids and is_nil(p.apagado_em)
      ),
      scope
    )
  end

  # Pastas de uma pasta (ou da raiz), legiveis pela regra do kernel.
  defp folders_query(%Scope{} = scope, nil) do
    KernelQueries.readable_folder(
      from(p in Folder, where: p.tekoa_id == ^scope.tekoa.id and is_nil(p.parent_id) and is_nil(p.apagado_em)),
      scope
    )
  end

  defp folders_query(%Scope{} = scope, parent_id) do
    KernelQueries.readable_folder(
      from(p in Folder, where: p.tekoa_id == ^scope.tekoa.id and p.parent_id == ^parent_id and is_nil(p.apagado_em)),
      scope
    )
  end

  # A travessa e o predio: a secao critica (a conferencia seguida do
  # veredito) fica em `gc_blob_verdict/1`, e o encaixe aqui e so a trava.
  defp gc_blob_row(%BlobGc{} = row) do
    BlobLock.run(row.blob_cid, fn -> gc_blob_verdict(row) end)
  end

  # O veredito de uma fila: referência viva (dedup) devolve os bytes para o
  # arquivo que os referencia e derruba a fila; sem referência, os bytes saem
  # do disco e a fila cai também. Falha de disco deixa a fila para a próxima
  # rodada de hora em hora.
  #
  # Tudo roda sob a travessa do CID (`Taina.Ybira.BlobLock`): o upload grava
  # os bytes ANTES de commitar a referência, então conferir fora da travessa
  # deixaria a resposta velha na hora entre a gravacao e o commit. A travessa
  # e local (a caixa e um no) e por CID: so o upload dos mesmos bytes espera
  # esta secao, que e uma consulta e um apagao no maximo.
  defp gc_blob_verdict(%BlobGc{} = row) do
    if blob_referenced?(row.blob_cid) do
      drop_blob_gc_row(row)
      :kept
    else
      case Disk.delete(Blobs.new(), Ypy.Cid.parse(row.blob_cid)) do
        :ok ->
          drop_blob_gc_row(row)
          :deleted

        # Bytes já fora do disco (rodada anterior morreu no meio): a fila cai.
        {:error, :not_found} ->
          drop_blob_gc_row(row)
          :deleted

        {:error, reason} ->
          Logger.warning("BlobGc: falha ao remover blob do disco, fila fica para a próxima rodada",
            reason: "#{row.blob_cid} #{inspect(reason)}"
          )

          :kept
      end
    end
  end

  defp image?("image/" <> _rest), do: true
  defp image?(_mime), do: false

  defp locked_upload(%Scope{} = scope, temporary_path, opts, cid) do
    BlobLock.run(Ypy.Cid.to_string(cid), fn ->
      within_tekoa(scope, fn ->
        Kernel.upload(Repo, Keys.new(), Blobs.new(), scope, temporary_path, opts)
      end)
    end)
  end

  defp maybe_enqueue_rendition(%Scope{} = scope, %File{} = file) do
    if image?(file.mime) do
      %{file_id: file.id, tekoa_public_id: scope.tekoa.public_id}
      |> Rendition.new()
      |> Oban.insert()
    end
  end

  # A purga de uma pasta remove a subarvore inteira. O CTE coleta os IDs dentro
  # da mesma comunidade; ownership e estado da lixeira sao verificados antes
  # dos deletes, dentro da mesma transacao.
  defp owned_subtree_folder_ids(%Scope{} = scope, root_id) do
    case Repo.query(
           """
           WITH RECURSIVE subtree AS (
             SELECT id, parent_id, dono_id FROM ybira_folders
             WHERE id = $1 AND tekoa_id = $2
             UNION ALL
             SELECT f.id, f.parent_id, f.dono_id FROM ybira_folders f
             JOIN subtree s ON f.parent_id = s.id
             WHERE f.tekoa_id = $2
           )
           SELECT id, dono_id FROM subtree
           """,
           [root_id, scope.tekoa.id]
         ) do
      {:ok, %{rows: rows}} ->
        owned_subtree_result(rows, scope.ava.id)

      {:error, _reason} = error ->
        error
    end
  end

  defp owned_subtree_result(rows, owner_id) do
    case Enum.find(rows, fn [_id, row_owner_id] -> row_owner_id != owner_id end) do
      nil -> {:ok, Enum.map(rows, fn [id, _row_owner_id] -> id end)}
      _other_owner -> {:error, :not_found}
    end
  end

  defp paginate_offset(query, limit, offset) do
    rows =
      query
      |> limit(^(limit + 1))
      |> offset(^offset)
      # Callers use batched association lookups instead of per-row preloads.
      # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
      |> Repo.all()

    if length(rows) > limit, do: {Enum.take(rows, limit), offset + limit}, else: {rows, nil}
  end

  # Sobe da pasta atual (primeira linha) e para no primeiro elo que não pode
  # ler: a cadeia fica com o trecho contíguo que termina nela, da raiz para a
  # pasta atual. O CTE devolve folha->raiz, então o `reverse` no fim entrega a
  # ordem que o breadcrumb espera (raiz->atual).
  defp purge_deleted_files_in_system(cutoff) do
    # Registros saem num só `delete_all` (com `select: f`, devolve as linhas
    # apagadas na mesma viagem). Arquivos saem ANTES das pastas: o FK de
    # `folder_id` (nilify) não dispara em lote vazio.
    {_count, files} =
      Repo.delete_all(
        from(f in File,
          where: not is_nil(f.apagado_em) and f.apagado_em < ^cutoff,
          select: f
        ),
        skip_tekoa_id: true
      )

    with :ok <- delete_thumbnails(files, tekoa_public_ids(files, skip_tekoa_id: true)) do
      # Pastas na lixeira só guardam metadados (sem bytes nem cota), apaga em
      # lote. `delete_folder/2` faz soft delete em cascata; sem isto, os
      # registros de pasta ficariam para sempre com `apagado_em` preenchido.
      Repo.delete_all(
        from(p in Folder, where: not is_nil(p.apagado_em) and p.apagado_em < ^cutoff),
        skip_tekoa_id: true
      )

      # Cota em lote: soma por Tekoa dos bytes apagados e ajusta uma vez por
      # comunidade, na MESMA transação dos deletes -- invariante de crash
      # preservado: registro e cota caem juntos, ou nada cai.
      Enum.each(bytes_per_tekoa(files), fn {tekoa_id, bytes} ->
        adjust_storage_used(tekoa_id, -bytes)
      end)

      # A corrida da dedup (revisão 0.1.0, 1c): apagar os bytes aqui, logo
      # após o commit da conferência, deixava uma janela em que um upload
      # concorrente commita um arquivo que compartilha o CID -- e o expurgo
      # apagava bytes de arquivo vivo. Os CIDs vão para a fila do GC
      # diferido, na MESMA transação dos deletes: registro apagado e blob
      # enfileirado caem juntos, ou nada cai.
      _ = enqueue_blob_gc(Enum.map(files, & &1.blob_cid))

      {:ok, files}
    end
  end

  defp purge_files(_tekoa_id, []), do: {:ok, 0}

  defp purge_files(tekoa_id, files) do
    ids = Enum.map(files, & &1.id)
    bytes = Enum.reduce(files, 0, &(&1.tamanho + &2))

    {count, _deleted} =
      Repo.delete_all(from(f in File, where: f.tekoa_id == ^tekoa_id and f.id in ^ids))

    if count == length(files) do
      tekoa = Repo.get!(Tekoa, tekoa_id)

      with :ok <- delete_thumbnails(files, %{tekoa_id => tekoa.public_id}) do
        adjust_storage_used(tekoa_id, -bytes)
        # enqueue_blob_gc/1 returns only {:ok, count}; Repo.insert_all raises on failure.
        # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingErrorHandling
        {:ok, _queued} = enqueue_blob_gc(Enum.map(files, & &1.blob_cid))
        {:ok, count}
      end
    else
      {:error, :not_found}
    end
  end

  defp purge_folders(tekoa_id, folder_ids) do
    {count, _deleted} =
      Repo.delete_all(from(f in Folder, where: f.tekoa_id == ^tekoa_id and f.id in ^folder_ids))

    if count == length(folder_ids), do: {:ok, count}, else: {:error, :not_found}
  end

  defp readable_chain(scope, rows) do
    rows
    |> Enum.take_while(&readable?(scope, &1))
    |> Enum.map(&%{rkey: &1.rkey, nome: &1.nome})
    |> Enum.reverse()
  end

  # O conjunto legivel (a regra de leitura do kernel no SQL, sem N+1), sem
  # limite de pagina: os agregados do painel contam tudo.
  defp readable_files_query(%Scope{} = scope) do
    KernelQueries.readable(from(f in File, where: f.tekoa_id == ^scope.tekoa.id and is_nil(f.apagado_em)), scope)
  end

  defp readable_folder_rkeys(_scope, [], _concessoes), do: %{}

  defp readable_folder_rkeys(%Scope{} = scope, folder_ids, concessoes) do
    folders =
      Map.new(
        Repo.all(from(p in Folder, where: p.id in ^folder_ids and is_nil(p.apagado_em))),
        fn p -> {p.id, p} end
      )

    Map.new(folder_ids, fn folder_id ->
      case Map.get(folders, folder_id) do
        nil ->
          {folder_id, nil}

        %Folder{} = folder ->
          readable? = Policy.can_read?(folder.zona, scope.ava.id, folder.dono_id, @tipo_folder, folder.rkey, concessoes)
          {folder_id, if(readable?, do: folder.rkey)}
      end
    end)
  end

  # The SQLite expression extracts the MIME prefix before its first slash.
  # Keep the fragment directly in both query clauses so Ecto can validate it.
  @doc "Armazenamento por tipo (painel): fotos, videos, documentos, outros."
  def storage_stats_by_kind(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      rows =
        scope
        |> readable_files_query()
        |> group_by(
          [f],
          fragment(
            "CASE WHEN instr(?, '/') = 0 THEN ? ELSE substr(?, 1, instr(?, '/') - 1) END",
            f.mime,
            f.mime,
            f.mime,
            f.mime
          )
        )
        |> select(
          [f],
          {fragment(
             "CASE WHEN instr(?, '/') = 0 THEN ? ELSE substr(?, 1, instr(?, '/') - 1) END",
             f.mime,
             f.mime,
             f.mime,
             f.mime
           ), sum(f.tamanho)}
        )
        # Aggregate MIME tuples; there are no associations to preload.
        # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
        |> Repo.all()

      {:ok, classify_storage_kinds(rows)}
    end)
  end

  # Fato da máquina, tekoa inteiro (não o subconjunto legível): a cota cobre
  # os bytes de todo mundo, incluída a casa de quem não leu (RFC_003 D2 é a
  # regra de leitura, não a de ocupação). A lixeira ainda ocupa até o expurgo,
  # então casa + praça + lixeira bate com `storage_stats/1` (`used_bytes`).
  @doc "Armazenamento por zona (armazenamento): casas, praca e lixeira em bytes."
  def storage_stats_by_zone(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      live =
        from(f in File,
          where: f.tekoa_id == ^scope.tekoa.id and is_nil(f.apagado_em),
          group_by: f.zona,
          select: {f.zona, sum(f.tamanho)}
        )
        # Aggregate zone tuples; there are no associations to preload.
        # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
        |> Repo.all()
        |> Map.new(fn {zona, bytes} -> {zona, to_integer(bytes)} end)

      lixeira =
        from(f in File,
          where: f.tekoa_id == ^scope.tekoa.id and not is_nil(f.apagado_em),
          select: sum(f.tamanho)
        )
        |> Repo.one()
        |> to_integer()

      {:ok, %{casa: Map.get(live, :casa, 0), praca: Map.get(live, :praca, 0), lixeira: lixeira}}
    end)
  end

  @doc "Tira da praca, de volta para a casa (kernel: `Ypy.Ybira.tirar_da_praca/5`)."
  def tirar_file_da_praca(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> Kernel.tirar_da_praca(Repo, Keys.new(), scope, @tipo_file, rkey) end)
  end

  def tirar_folder_da_praca(%Scope{} = scope, rkey) when is_binary(rkey) do
    within_tekoa(scope, fn -> change_folder_tree_zone(scope, rkey, :tirar) end)
  end

  @doc "Quantos arquivos e bytes há na lixeira da Tekoa (painel, agregado sem dono)."
  def trash_stats(%Scope{} = scope) do
    within_tekoa(scope, fn ->
      stats =
        Repo.one(
          from(f in File,
            where: f.tekoa_id == ^scope.tekoa.id and not is_nil(f.apagado_em),
            select: %{count: count(f.id), bytes: sum(f.tamanho)}
          )
        )

      {:ok, %{count: stats.count, bytes: to_integer(stats.bytes)}}
    end)
  end

  defp resource_rkeys(resources, tipo) do
    rkeys = for {^tipo, rkey} when is_binary(rkey) <- resources, do: rkey
    Enum.uniq(rkeys)
  end

  defp sum_counts(%Scope{} = scope, ids) do
    folders = counts_by(scope, :folder, ids)
    files = counts_by(scope, :file, ids)

    Map.new(ids, fn id ->
      {id, Map.get(folders, id, 0) + Map.get(files, id, 0)}
    end)
  end

  defp tekoa_public_ids(files, opts) do
    tekoa_ids = for %File{mime: mime, tekoa_id: tekoa_id} <- files, image?(mime), do: tekoa_id
    tekoa_ids = Enum.uniq(tekoa_ids)

    from(t in Tekoa, where: t.id in ^tekoa_ids, select: {t.id, t.public_id})
    # Tuple projection used for thumbnail paths; no associations are read.
    # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
    |> Repo.all(opts)
    |> Map.new()
  end

  # `sum/1` sobre inteiro volta como `Decimal` no SQLite; normalizamos para
  # inteiro (bytes são sempre inteiros) antes de somar no acumulador.
  defp to_integer(nil), do: 0
  defp to_integer(%Decimal{} = bytes), do: Decimal.to_integer(bytes)
  defp to_integer(bytes) when is_integer(bytes), do: bytes

  defp trashed_file(%Scope{} = scope, rkey) do
    case KernelStore.get_file(Repo, scope.tekoa.id, rkey, true) do
      %File{dono_id: dono_id} = file when dono_id == scope.ava.id -> {:ok, file}
      _ -> {:error, :not_found}
    end
  end

  # Linhas chegam da pasta atual para a raiz (depth 0 -> 32). O teto existe
  # para um grafo corrompido: sem ele, um ciclo no parent_id faria a consulta
  # crescer o resultado até estourar.
  # `zona` chega do SQL como texto; os átomos existem (Ecto.Enum do schema).
  defp photo_metadata!(file_id) do
    case Repo.one(from(p in Photo, where: p.file_id == ^file_id)) do
      nil -> %{}
      photo -> photo.metadata || %{}
    end
  end

  defp trashed_subtree_folders(%Scope{} = scope, folder_ids) do
    folders = Repo.all(from(f in Folder, where: f.tekoa_id == ^scope.tekoa.id and f.id in ^folder_ids))

    if length(folders) == length(folder_ids) and
         Enum.all?(folders, &(&1.dono_id == scope.ava.id and not is_nil(&1.apagado_em))) do
      {:ok, folders}
    else
      {:error, :invalid_status}
    end
  end

  defp trashed_subtree_files(%Scope{} = scope, folder_ids) do
    files = Repo.all(from(f in File, where: f.tekoa_id == ^scope.tekoa.id and f.folder_id in ^folder_ids))

    if Enum.all?(files, &(&1.dono_id == scope.ava.id and not is_nil(&1.apagado_em))) do
      {:ok, files}
    else
      {:error, :invalid_status}
    end
  end

  defp zona_atom("casa"), do: :casa
  defp zona_atom("praca"), do: :praca

  @doc """
  O upload: o kernel le o arquivo, confere cota e MIME, guarda os bytes no
  `Ypy.BlobStore` e commita blob, record, arquivo e cota com a entrada na
  cadeia. O mime vem dos magic bytes (produto); a rendition de imagem
  enfileira depois do commit (best-effort: a foto existe sem thumbnail).

  O kernel inteiro roda sob a travessa do CID dos bytes (`Taina.Ybira.BlobLock`):
  os bytes entram no disco antes de a referencia commitar, e o GC diferido so
  pode apagar bytes sem referencia DENTRO da mesma travessa. Sem ela, o GC
  conferiria referencias entre a gravacao dos bytes e o commit, apagaria o
  blob e o arquivo commitaria apontando para bytes que nao existem mais. So
  espera a vez quem sobe os MESMOS bytes (mesmo CID, a corrida da dedup);
  upload de conteudo diferente nunca espera.
  """
  def upload(%Scope{} = scope, temporary_path, opts \\ []) do
    opts = [
      mime: MimeDetector.detect(temporary_path),
      nome: Keyword.get(opts, :filename, Path.basename(temporary_path)),
      folder: Keyword.get(opts, :folder_rkey)
    ]

    with {:ok, %{size: size}} <- Elixir.File.stat(temporary_path),
         :ok <- blob_size_allowed?(size),
         {:ok, cid} <- blob_cid(temporary_path),
         {:ok, file} <- locked_upload(scope, temporary_path, opts, cid) do
      maybe_enqueue_rendition(scope, file)
      {:ok, file}
    end
  end

  defp within_tekoa(%Scope{} = scope, cb), do: Repo.with_tekoa(scope.tekoa.public_id, cb)

  # A listagem de arquivos e composta sobre as queries do kernel (que trazem a
  # regra de leitura no nivel do SQL). O `nil` e raiz (arquivos soltos): o
  # kernel so filtra pasta quando ha uma, a raiz precisa de filtro proprio.
  defp files_query(%Scope{} = scope, nil) do
    scope
    |> base()
    |> where([f], is_nil(f.folder_id))
  end

  defp files_query(%Scope{} = scope, %Folder{} = folder) do
    scope
    |> base()
    |> where([f], f.folder_id == ^folder.id)
  end

  defp files_query(%Scope{} = scope, rkey) when is_binary(rkey) do
    case KernelStore.get_folder(Repo, scope.tekoa.id, rkey) do
      nil -> where(base(scope), [f], false)
      folder -> files_query(scope, folder)
    end
  end

  defp maybe_filter_zone(query, nil), do: query
  defp maybe_filter_zone(query, zona), do: where(query, [item], item.zona == ^zona)

  defp root_listing_zone(nil, zona), do: zona
  defp root_listing_zone(_folder, _zona), do: nil

  defp base(%Scope{} = scope) do
    KernelQueries.readable(
      from(f in File, where: f.tekoa_id == ^scope.tekoa.id and is_nil(f.apagado_em), order_by: [desc: f.rkey]),
      scope
    )
  end

  # A concessão vale pelo tipo de coleção, como no SQL do kernel: o rkey
  # sozinho não abre a porta. Os elos que chegam aqui (pai do arquivo e CTE
  # do breadcrumb) são todos da coleção de pastas; o caminho do arquivo fica
  # no kernel, com o seu tipo.
  defp readable?(scope, row) do
    concessoes = Store.concessoes_ativas(Repo, scope.tekoa.id, scope.ava.id)
    Policy.can_read?(row.zona, scope.ava.id, row.dono_id, @tipo_folder, row.rkey, concessoes)
  end

  defp quota_check(tekoa_id, byte_size) do
    tekoa = Repo.get!(Tekoa, tekoa_id)

    cond do
      is_nil(tekoa.storage_quota_bytes) -> :ok
      tekoa.storage_used_bytes + byte_size <= tekoa.storage_quota_bytes -> :ok
      true -> {:error, :storage_quota_exceeded}
    end
  end

  defp resolve_folder(_scope, nil), do: {:ok, nil}

  defp resolve_folder(%Scope{} = scope, rkey) when is_binary(rkey) do
    case KernelStore.get_folder(Repo, scope.tekoa.id, rkey) do
      nil -> {:error, :not_found}
      folder -> {:ok, folder}
    end
  end

  # Destino de mutação (criar dentro de, mover para): a pasta precisa existir
  # E ser sua. A navegação (`list_folder_contents`) fica com a regra de
  # leitura; aqui quem recebe o item é o dono do destino. `:not_found` para
  # pasta alheia, sem vazar que ela existe.
  defp resolve_owned_folder_id(_scope, nil), do: {:ok, nil}

  defp resolve_owned_folder_id(%Scope{} = scope, rkey) when is_binary(rkey) do
    case KernelStore.get_folder(Repo, scope.tekoa.id, rkey) do
      nil -> {:error, :not_found}
      folder -> if scope.ava.id == folder.dono_id, do: {:ok, folder.id}, else: {:error, :not_found}
    end
  end

  defp fetch_owned_folder(%Scope{} = scope, rkey) do
    case KernelStore.get_folder(Repo, scope.tekoa.id, rkey) do
      nil -> {:error, :not_found}
      folder -> if scope.ava.id == folder.dono_id, do: {:ok, folder}, else: {:error, :not_found}
    end
  end

  # Mover `folder_id` para baixo de `new_parent_id` fecharia um ciclo se
  # `folder_id` for o próprio `new_parent_id` ou um ancestral dele.
  defp ensure_acyclic(_folder_id, nil), do: :ok

  defp ensure_acyclic(folder_id, new_parent_id) do
    case ancestor_or_self?(new_parent_id, folder_id) do
      {:ok, true} -> {:error, :circular_reference}
      {:ok, false} -> :ok
      {:error, _reason} = error -> error
    end
  end

  # Uma única CTE recursiva sobe a cadeia de ancestrais de `start_id` (incluindo
  # ele) e responde se `folder_id` aparece lá, sem N+1 nem recursão Elixir
  # ilimitada. Roda sob o contexto de Tekoa.
  defp ancestor_or_self?(start_id, folder_id) do
    case Repo.query(
           """
           WITH RECURSIVE ancestors AS (
             SELECT id, parent_id FROM ybira_folders WHERE id = $1
             UNION ALL
             SELECT f.id, f.parent_id FROM ybira_folders f
             JOIN ancestors a ON f.id = a.parent_id
           )
           SELECT count(*) FROM ancestors WHERE id = $2
           """,
           [start_id, folder_id]
         ) do
      {:ok, %{rows: [[count]]}} -> {:ok, count > 0}
      {:error, _reason} = error -> error
    end
  end

  # Soft delete em cascata sem recursão Elixir: uma CTE coleta a subárvore (raiz
  # + descendentes não-deletados) e dois `update_all` marcam arquivos e pastas.
  # O carimbo é do LOTE (um só horário para a subárvore toda) e precisa ser
  # estritamente maior que qualquer `apagado_em` já presente na subárvore
  # INTEIRA: `agora/0` trunca ao segundo, e um item apagado por conta própria
  # no mesmo segundo da pasta herdaria o carimbo e voltaria junto na
  # restauração (que casa pelo `apagado_em` exato dela).
  defp soft_delete_tree(tekoa_id, root_id) do
    with {:ok, folder_ids} <- descendant_folder_ids(root_id),
         {:ok, subtree_ids} <- subtree_folder_ids(root_id) do
      now = batch_timestamp(tekoa_id, subtree_ids)

      Repo.update_all(
        from(f in File,
          where: f.tekoa_id == ^tekoa_id and f.folder_id in ^folder_ids and is_nil(f.apagado_em)
        ),
        set: [apagado_em: now]
      )

      Repo.update_all(
        from(p in Folder,
          where: p.tekoa_id == ^tekoa_id and p.id in ^folder_ids and is_nil(p.apagado_em)
        ),
        set: [apagado_em: now]
      )

      :ok
    end
  end

  defp descendant_folder_ids(root_id) do
    case Repo.query(
           """
           WITH RECURSIVE subtree AS (
             SELECT id FROM ybira_folders WHERE id = $1
             UNION ALL
             SELECT f.id FROM ybira_folders f
             JOIN subtree s ON f.parent_id = s.id
             WHERE f.apagado_em IS NULL
           )
           SELECT id FROM subtree
           """,
           [root_id]
         ) do
      {:ok, %{rows: rows}} -> {:ok, List.flatten(rows)}
      {:error, _reason} = error -> error
    end
  end

  # O maior `apagado_em` da subárvore inteira (pastas e arquivos, inclusive o
  # que já estava na lixeira por conta própria). Nada ainda: o carimbo é o
  # agora truncado, como sempre foi.
  defp batch_timestamp(_tekoa_id, []), do: agora()

  defp batch_timestamp(tekoa_id, subtree_ids) do
    file_last =
      Repo.one(
        from(f in File,
          where: f.tekoa_id == ^tekoa_id and f.folder_id in ^subtree_ids and not is_nil(f.apagado_em),
          select: max(f.apagado_em)
        )
      )

    folder_last =
      Repo.one(
        from(p in Folder,
          where: p.tekoa_id == ^tekoa_id and p.id in ^subtree_ids and not is_nil(p.apagado_em),
          select: max(p.apagado_em)
        )
      )

    case Enum.reject([file_last, folder_last], &is_nil/1) do
      [] -> agora()
      taken -> maybe_bump_until_after(agora(), Enum.max_by(taken, &DateTime.to_unix/1))
    end
  end

  # O carimbo do lote, em passo único: o `agora` quando ele já é estritamente
  # maior que o maior `apagado_em` da subárvore, senão um segundo depois dele.
  # Dois lotes no mesmo segundo não podem compartilhar a chave que a
  # restauração usa. Sem laço: um `apagado_em` muito à frente do relógio (um
  # relógio adiantado que foi corrigido) não pode prender a requisição
  # subindo segundo a segundo.
  defp maybe_bump_until_after(%DateTime{} = candidate, %DateTime{} = taken) do
    if DateTime.after?(candidate, taken), do: candidate, else: DateTime.shift(taken, second: 1)
  end

  # A pasta NA lixeira, dona por quem restaura: a loja só devolve pasta da
  # lixeira com opt-in (`lixeira?`), e o guard de dono fica aqui, com o mesmo
  # silêncio de `fetch_owned_folder/2` para pasta alheia (`:not_found`, sem
  # vazar que existe).
  defp fetch_trashed_owned_folder(%Scope{} = scope, rkey) do
    case KernelStore.get_folder(Repo, scope.tekoa.id, rkey, true) do
      nil ->
        {:error, :not_found}

      folder ->
        cond do
          folder.dono_id != scope.ava.id -> {:error, :not_found}
          is_nil(folder.apagado_em) -> {:error, :invalid_status}
          true -> {:ok, folder}
        end
    end
  end

  # Restaura a subárvore apagada JUNTO com a pasta: arquivos e pastas com o
  # MESMO `apagado_em` dela (o `soft_delete_tree/2` marca a subárvore toda de
  # uma vez, com um só horário). Um item apagado antes, por conta própria,
  # fica na lixeira.
  defp restore_folder_subtree(%Scope{} = scope, folder) do
    with {:ok, folder_ids} <- subtree_folder_ids(folder.id) do
      Repo.update_all(
        from(p in Folder, where: p.id in ^folder_ids and p.apagado_em == ^folder.apagado_em),
        set: [apagado_em: nil]
      )

      Repo.update_all(
        from(f in File, where: f.folder_id in ^folder_ids and f.apagado_em == ^folder.apagado_em),
        set: [apagado_em: nil]
      )

      folder = Repo.one!(from(p in Folder, where: p.id == ^folder.id))
      restore_to_root_if_orphaned(scope, folder)
    end
  end

  # Mesma CTE de `descendant_folder_ids/1`, sem o filtro de lixeira: para
  # restaurar, os descendentes estão (normalmente) apagados.
  defp subtree_folder_ids(root_id) do
    case Repo.query(
           """
           WITH RECURSIVE subtree AS (
             SELECT id FROM ybira_folders WHERE id = $1
             UNION ALL
             SELECT f.id FROM ybira_folders f
             JOIN subtree s ON f.parent_id = s.id
           )
           SELECT id FROM subtree
           """,
           [root_id]
         ) do
      {:ok, %{rows: rows}} -> {:ok, List.flatten(rows)}
      {:error, _reason} = error -> error
    end
  end

  # Restaurar só limpa `apagado_em`: se a pasta-pai também estiver na lixeira,
  # o item restaurado não apareceria em lugar nenhum: nem na raiz (o pai
  # preenchido o tira da listagem de soltos) nem em pasta listável (a de
  # origem está fora). Nesse caso ele volta solto na raiz, que é onde
  # "restaurar" o torna visível de novo.
  defp restore_to_root_if_orphaned(_scope, %File{folder_id: nil} = file), do: {:ok, file}

  defp restore_to_root_if_orphaned(%Scope{} = scope, %File{} = file) do
    if folder_orphaned?(file.folder_id) do
      Logger.info("Ybira: arquivo restaurado solto na raiz, a pasta dele está na lixeira",
        file_id: file.id,
        reason: "folder_id=#{file.folder_id}"
      )

      # O verbo do kernel (`mover/5`, nil = solto na raiz): a troca de pasta
      # vira uma versão nova do arquivo na cadeia assinada, não um update
      # calado no banco. O erro dele sobe para a borda (`Error.reply`) em vez
      # de virar MatchError, e o `with_tekoa/2` desfaz a restauração: um
      # arquivo restaurado com a pasta-pai na lixeira não fica pela metade.
      Kernel.mover(Repo, Keys.new(), scope, file.rkey, nil)
    else
      {:ok, file}
    end
  end

  # O kernel não tem mover-pasta (o verbo é do produto, `move_folder/3`): a
  # troca de pai da pasta restaurada segue sem entrada na cadeia (mesmo gap
  # documentado no `move_folder/3`).
  defp restore_to_root_if_orphaned(_scope, %Folder{parent_id: nil} = folder), do: {:ok, folder}

  defp restore_to_root_if_orphaned(_scope, %Folder{} = folder) do
    if folder_orphaned?(folder.parent_id) do
      Logger.info("Ybira: pasta restaurada solta na raiz, a pasta-pai está na lixeira",
        reason: "folder_id=#{folder.id} parent_id=#{folder.parent_id}"
      )

      Repo.update(Folder.changeset(folder, %{parent_id: nil}))
    else
      {:ok, folder}
    end
  end

  # A pasta-pai sumiu do registro (expurgada; com FK ativa, caso defensivo)
  # ou está na lixeira: sem ela, o item não tem listagem em tela nenhuma.
  defp folder_orphaned?(folder_id) do
    case Repo.one(from(p in Folder, where: p.id == ^folder_id)) do
      nil -> true
      %Folder{apagado_em: nil} -> false
      %Folder{} -> true
    end
  end

  # Ordenação dinâmica (nome/data/tamanho x asc/desc), com `rkey` como desempate
  # estável. A paginação aqui é por offset (não keyset), o que permite qualquer
  # ordem sem cursor composto, suficiente para uma caixa de comunidade.
  @sort_fields ~W(date name size)a
  @sort_dirs ~W(asc desc)a

  defp normalize_sort({field, dir}) when field in @sort_fields and dir in @sort_dirs, do: {field, dir}
  defp normalize_sort(_other), do: {:date, :desc}

  defp apply_file_sort(query, {:name, dir}), do: order_by(query, [f], [{^dir, f.nome}, {^dir, f.rkey}])
  defp apply_file_sort(query, {:size, dir}), do: order_by(query, [f], [{^dir, f.tamanho}, {^dir, f.rkey}])
  defp apply_file_sort(query, {:date, dir}), do: order_by(query, [f], [{^dir, f.inserted_at}, {^dir, f.rkey}])

  defp apply_folder_sort(query, {:name, dir}), do: order_by(query, [p], [{^dir, p.nome}])
  defp apply_folder_sort(query, {:date, dir}), do: order_by(query, [p], [{^dir, p.inserted_at}])
  # Pastas não têm tamanho; ao ordenar por tamanho, mantêm ordem alfabética.
  defp apply_folder_sort(query, {:size, _dir}), do: order_by(query, [p], asc: p.nome)

  defp fetch_attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, to_string(key))
  end

  # Paginação por rkey (o TID e ordenavel por tempo; o cursor e o rkey do
  # ultimo item da pagina). Uma linha a mais diz se ha proxima pagina.
  defp page(query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    query =
      case Keyword.get(opts, :after_cursor) do
        nil -> query
        cursor when is_binary(cursor) -> where(query, [f], f.rkey < ^cursor)
      end

    rows =
      query
      |> limit(^(limit + 1))
      # Callers use batched association lookups instead of per-row preloads.
      # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
      |> Repo.all()

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      %{items: page, next_cursor: List.last(page).rkey}
    else
      %{items: rows, next_cursor: nil}
    end
  end

  defp agora, do: DateTime.truncate(DateTime.utc_now(), :second)
end
