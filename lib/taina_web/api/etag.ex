defmodule TainaWeb.API.Etag do
  @moduledoc """
  Requisicoes condicionais nas colecoes (contrato review 0.1.0, D): ETag
  fraca `W/"<count>-<max_updated_at_unix>"` sobre o conjunto legivel INTEIRO
  (nao sobre a pagina: paginar nao muda o hash) e `304` sem corpo quando o
  `If-None-Match` do cliente ainda bate. O hash e do scope: cada pessoa ve o
  do conjunto que ela mesma le.

  Os agregados vao pelo mesmo caminho das listagens: a regra das duas zonas
  e a do kernel (`Ypy.Ybira.Queries.readable/2`, a que as listagens usam) e
  os filtros de base (tekoa, lixeira, mime, pasta) espelham os contextos --
  se um contexto mudar a base, o Etag acompanha.
  """

  import Ecto.Query
  import Plug.Conn

  alias Taina.Jaci.Photo
  alias Taina.Repo
  alias Taina.Ybira
  alias Taina.Ybira.Manifest
  alias Ypy.Scope
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder
  alias Ypy.Ybira.Queries, as: KernelQueries

  @doc "O token do ETag: a contagem e o maior `updated_at` em unix (0 quando o conjunto e vazio)."
  @spec token(non_neg_integer(), nil | DateTime.t()) :: String.t()
  def token(count, nil) when is_integer(count), do: "W/\"#{count}-0\""
  def token(count, %DateTime{} = at) when is_integer(count), do: "W/\"#{count}-#{DateTime.to_unix(at)}\""

  @doc """
  O ETag bate com o `If-None-Match` do cliente? Bate: `{:not_modified, conn}`
  com o `304` sem corpo (o ETag segue na resposta, para o cliente conferir).
  Nao bate: `{:fresh, conn}` com o ETag anotado, e a listagem segue.
  """
  @spec handle(Plug.Conn.t(), String.t()) :: {:not_modified, Plug.Conn.t()} | {:fresh, Plug.Conn.t()}
  def handle(conn, etag) when is_binary(etag) do
    conn = put_resp_header(conn, "etag", etag)

    if matches?(if_none_match(conn), etag) do
      {:not_modified, send_resp(conn, 304, "")}
    else
      {:fresh, conn}
    end
  end

  @doc "O conjunto legivel inteiro (o manifesto de backup e os recentes)."
  @spec readable_files(Scope.t()) :: String.t()
  def readable_files(%Scope{} = scope) do
    {:ok, etag} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok, scope |> readable_query() |> tag()}
      end)

    etag
  end

  @doc "O conjunto legivel de fotos e videos (a grade e a linha do tempo)."
  @spec photos(Scope.t()) :: String.t()
  def photos(%Scope{} = scope) do
    {:ok, etag} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok,
         scope
         |> readable_query()
         |> where([f], like(f.mime, "image/%") or like(f.mime, "video/%"))
         |> tag()}
      end)

    etag
  end

  @doc """
  O conteudo de uma pasta: os arquivos legiveis dela, as subpastas e os
  metadados de foto, porque os tres entram na resposta do `/contents` (o
  ETag que mente sobre o conjunto deixa o cliente com a lista velha).
  """
  @spec folder_files(Scope.t(), nil | String.t()) :: {:ok, String.t()} | {:error, :not_found | :forbidden}
  def folder_files(%Scope{} = scope, nil) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      files = scope |> readable_query() |> where([f], is_nil(f.folder_id))
      folders = scope |> readable_folders() |> where([p], is_nil(p.parent_id))
      {:ok, contents_tag(files, folders)}
    end)
  end

  def folder_files(%Scope{} = scope, folder_rkey) when is_binary(folder_rkey) do
    case Ybira.get_folder(scope, folder_rkey) do
      {:ok, folder} ->
        Repo.with_tekoa(scope.tekoa.public_id, fn ->
          files = scope |> readable_query() |> where([f], f.folder_id == ^folder.id)
          folders = scope |> readable_folders() |> where([p], p.parent_id == ^folder.id)
          {:ok, contents_tag(files, folders)}
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "O lixo da propria pessoa (a mesma base da listagem da lixeira)."
  @spec trash(Scope.t()) :: String.t()
  def trash(%Scope{} = scope) do
    {:ok, etag} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok, scope |> trash_query() |> tag()}
      end)

    etag
  end

  # A base e a regra de leitura do kernel no SQL, a mesma das listagens de
  # arquivo (`Ybira.list_recent`, `Jaci.list_photos`, manifesto): a publica
  # do manifesto, para as duas bases nao divergirem (e o 304 nao mentir).
  defp readable_query(%Scope{} = scope), do: Manifest.readable_query(scope)

  # A mesma regra para pastas (o `/contents` lista as subpastas).
  defp readable_folders(%Scope{} = scope) do
    KernelQueries.readable_folder(
      from(p in Folder, where: p.tekoa_id == ^scope.tekoa.id and is_nil(p.apagado_em)),
      scope
    )
  end

  defp trash_query(%Scope{} = scope) do
    from(f in File,
      where: f.tekoa_id == ^scope.tekoa.id and f.dono_id == ^scope.ava.id and not is_nil(f.apagado_em)
    )
  end

  # A medida do conjunto: uma contagem e o maior `updated_at` dele. O join
  # com a foto do produto entra na mesma medida porque a rendicao muda
  # `jaci_photos.updated_at` (e nao o do arquivo): sem ela, um 304 depois do
  # worker mantinha o cliente em `"rendition": "pending"`.
  defp tag(query) do
    %{
      count: count,
      file_last: file_last,
      photo_last: photo_last
    } =
      Repo.one(
        from(f in query,
          left_join: p in Photo,
          on: p.file_id == f.id,
          select: %{count: count(f.id), file_last: max(f.updated_at), photo_last: max(p.updated_at)}
        )
      )

    token(count, latest([file_last, photo_last]))
  end

  # O `/contents` mede os dois lados da resposta: os arquivos (com os
  # metadados de foto, como acima) e as subpastas -- criar uma pasta dentro
  # nao mexe em arquivo nenhum, e o cliente teria que ver a pasta nova.
  defp contents_tag(files_query, folders_query) do
    files =
      Repo.one(
        from(f in files_query,
          left_join: p in Photo,
          on: p.file_id == f.id,
          select: %{count: count(f.id), file_last: max(f.updated_at), photo_last: max(p.updated_at)}
        )
      )

    folders = Repo.one(from(p in folders_query, select: %{count: count(p.id), last: max(p.updated_at)}))

    token(files.count + folders.count, latest([files.file_last, files.photo_last, folders.last]))
  end

  defp latest(dates) do
    case Enum.reject(dates, &is_nil/1) do
      [] -> nil
      dates -> Enum.max(dates, DateTime)
    end
  end

  # O header pode vir repetido e com varios ETags num valor so. `*` casa com
  # qualquer representacao existente (RFC 9110, secao 13.1.2) e a comparacao
  # e fraca: um proxy pode ecoar o token sem o `W/` da frente.
  defp matches?(tokens, etag) do
    "*" in tokens or Enum.any?(tokens, &(String.trim_leading(&1, "W/") == String.trim_leading(etag, "W/")))
  end

  defp if_none_match(conn) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
  end
end
