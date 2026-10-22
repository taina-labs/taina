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

  alias Taina.Repo
  alias Taina.Ybira
  alias Ypy.Scope
  alias Ypy.Ybira.File
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

    if etag in if_none_match(conn) do
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

  @doc "Os arquivos legiveis de uma pasta (os soltos, quando nao ha)."
  @spec folder_files(Scope.t(), nil | String.t()) :: {:ok, String.t()} | {:error, :not_found | :forbidden}
  def folder_files(%Scope{} = scope, nil) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      {:ok, scope |> readable_query() |> where([f], is_nil(f.folder_id)) |> tag()}
    end)
  end

  def folder_files(%Scope{} = scope, folder_rkey) when is_binary(folder_rkey) do
    case Ybira.get_folder(scope, folder_rkey) do
      {:ok, folder} ->
        Repo.with_tekoa(scope.tekoa.public_id, fn ->
          {:ok, scope |> readable_query() |> where([f], f.folder_id == ^folder.id) |> tag()}
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
  # arquivo (`Ybira.list_recent`, `Jaci.list_photos`, manifesto).
  defp readable_query(%Scope{} = scope) do
    KernelQueries.readable(
      from(f in File, where: f.tekoa_id == ^scope.tekoa.id and is_nil(f.apagado_em)),
      scope
    )
  end

  defp trash_query(%Scope{} = scope) do
    from(f in File,
      where: f.tekoa_id == ^scope.tekoa.id and f.dono_id == ^scope.ava.id and not is_nil(f.apagado_em)
    )
  end

  # A medida do conjunto: uma contagem e o maior updated_at dele.
  defp tag(query) do
    %{count: count, last: last} =
      Repo.one(from(f in query, select: %{count: count(f.id), last: max(f.updated_at)}))

    token(count, last)
  end

  # O header pode vir repetido e com varios ETags num valor so; compara
  # exato, que e o que o cliente ecoa de volta.
  defp if_none_match(conn) do
    conn
    |> get_req_header("if-none-match")
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
  end
end
