defmodule Taina.Ybira.Manifest do
  @moduledoc """
  O manifesto de arquivos, do mais antigo para o mais novo (o rkey e um TID,
  ordenavel por tempo), um `sha256` por linha. O modo padrao lista arquivos
  legiveis e ativos. O modo `:mirror` lista somente os arquivos do dono,
  incluindo a lixeira.

  O cliente de backup lista o manifesto, compara com o que ja tem localmente e
  baixa so o que falta.
  """

  import Ecto.Query

  alias Taina.Repo
  alias Ypy.Scope
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Queries, as: KernelQueries

  @default_limit 200
  @type file :: File.t()
  @type mode :: :readable | :mirror
  @type opts :: keyword()
  @type query :: Ecto.Query.t()
  @type scope :: Scope.t()
  @type text :: String.t()

  @doc """
  A pagina do manifesto: `{:ok, %{items: [File], next_cursor: rkey | nil}}`.
  O `:after` e o rkey do ultimo item da pagina anterior; o `:limit` chega da
  borda ja parseado (padrao 200, teto 1000, em `TainaWeb.API.Query`). O modo
  padrao e `:readable`; `:mirror` seleciona os arquivos do dono, inclusive a
  lixeira.
  """
  @spec page(scope(), opts()) ::
          {:ok, %{items: [file()], next_cursor: text() | nil}}
  def page(%Scope{} = scope, opts \\ []) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      limit = Keyword.get(opts, :limit, @default_limit)

      rows =
        scope
        |> collection_query(Keyword.get(opts, :mode, :readable))
        |> order_by([f], asc: f.rkey)
        |> maybe_apply_cursor(Keyword.get(opts, :after))
        |> limit(^(limit + 1))
        # The API serializer uses batched lookups instead of per-file preloads.
        # credo:disable-for-next-line OeditusCredo.Check.Warning.MissingPreload
        |> Repo.all()

      if length(rows) > limit do
        page = Enum.take(rows, limit)
        {:ok, %{items: page, next_cursor: List.last(page).rkey}}
      else
        {:ok, %{items: rows, next_cursor: nil}}
      end
    end)
  end

  @doc """
  O conjunto legivel inteiro, sem ordem de paginacao por fora: a base dos
  agregados do ETag da colecao (`TainaWeb.API.Etag`), que conta e mede o
  `updated_at` maximo sobre ele.
  """
  @spec collection_query(scope(), mode()) :: query()
  def collection_query(%Scope{} = scope, :readable) do
    KernelQueries.readable(
      from(f in File, where: f.tekoa_id == ^scope.tekoa.id and is_nil(f.apagado_em)),
      scope
    )
  end

  def collection_query(%Scope{} = scope, :mirror) do
    from(f in File, where: f.tekoa_id == ^scope.tekoa.id and f.dono_id == ^scope.ava.id)
  end

  @doc "The default readable, live-file collection."
  @spec readable_query(scope()) :: query()
  def readable_query(%Scope{} = scope), do: collection_query(scope, :readable)

  # O cursor e o rkey do ultimo item da pagina anterior; a pagina seguinte e
  # o que vem depois dele (rkey asc).
  defp maybe_apply_cursor(query, <<_byte, _rest::binary>> = rkey), do: where(query, [f], f.rkey > ^rkey)

  defp maybe_apply_cursor(query, _cursor), do: query
end
