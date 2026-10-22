defmodule Taina.Jaci do
  @moduledoc """
  Jaci-lite, a galeria de fotos da comunidade.

  Jaci é uma camada de **leitura** sobre o Ybira (RFC 002, D4): consulta os
  arquivos de imagem do kernel (`Ypy.Ybira.File`, `mime` de imagem e video)
  sob a mesma regra de leitura (a do kernel, no nivel do SQL) e os apresenta
  como grade (`list_photos/2`) e linha do tempo (`timeline/2`). Não grava nem
  muta nada; upload, thumbnail e soft delete são do Ybira.

  Como todo context, recebe um scope (`Ypy.Scope`) e roda dentro de
  `Repo.with_tekoa/2`. A paginação da grade segue a ordem de upload (rkey
  decrescente, o TID é ordenável por tempo); a linha do tempo ordena pela data
  efetiva da foto (`effective_at` de `ybira_files`, que o worker de renditions
  preenche com o EXIF, ou o instante do upload como fallback), exigindo um
  cursor composto `(data, id)`.
  """

  import Ecto.Query

  alias Taina.Jaci.Timeline
  alias Taina.Repo
  alias Ypy.Scope
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Queries, as: KernelQueries

  @default_limit 50

  @doc "A grade da galeria: fotos e videos legiveis, da mais recente para a mais antiga."
  def list_photos(%Scope{} = scope, opts \\ []) do
    within_tekoa(scope, fn ->
      query =
        scope
        |> readable_photos()
        |> apply_zona(Keyword.get(opts, :zona))
        |> apply_grid_cursor(Keyword.get(opts, :after_cursor))

      {items, next_cursor} = fetch_grid_page(query, opts)
      {:ok, %{items: items, next_cursor: next_cursor}}
    end)
  end

  @doc "A linha do tempo: as mesmas fotos, agrupadas pela data efetiva (EXIF ou upload)."
  def timeline(%Scope{} = scope, opts \\ []) do
    within_tekoa(scope, fn ->
      {rows, next_cursor} = fetch_timeline_page(scope, opts)
      {:ok, %{groups: Timeline.group_by_date(rows), next_cursor: next_cursor}}
    end)
  end

  defp within_tekoa(%Scope{} = scope, cb), do: Repo.with_tekoa(scope.tekoa.public_id, cb)

  # O conjunto legivel de fotos e videos: regra de leitura do kernel no SQL.
  # Sem ordem: a grade ordena por upload (id), a linha do tempo pela data
  # efetiva -- e Ecto concatena `order_by` em vez de substituir.
  defp readable_photos(%Scope{} = scope) do
    KernelQueries.readable(
      from(f in File,
        where: f.tekoa_id == ^scope.tekoa.id and is_nil(f.apagado_em),
        where: like(f.mime, "image/%") or like(f.mime, "video/%")
      ),
      scope
    )
  end

  # A zona entra NA consulta, nao depois da pagina: se o filtro mora na tela,
  # o cursor caminha no conjunto inteiro e a aba de zona recebe paginas
  # curtas (e fotos que so aparecem depois de varios carregamentos). Sem
  # zona (`:tudo` da tela), nenhum filtro a mais.
  defp apply_zona(query, nil), do: query
  defp apply_zona(query, zona) when is_atom(zona), do: where(query, [f], f.zona == ^zona)

  # --- Grade: keyset por id (alinhado ao upload) ---

  defp fetch_grid_page(query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    rows =
      query
      |> order_by([f], desc: f.id)
      |> limit(^(limit + 1))
      |> Repo.all()

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      {page, encode_id_cursor(List.last(page))}
    else
      {rows, nil}
    end
  end

  defp apply_grid_cursor(query, nil), do: query

  defp apply_grid_cursor(query, cursor) when is_binary(cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, <<id::64>>} -> where(query, [f], f.id < ^id)
      _ -> query
    end
  end

  defp encode_id_cursor(%{id: id}), do: Base.url_encode64(<<id::64>>, padding: false)

  # --- Linha do tempo: keyset composto (data efetiva, id) ---
  #
  # A data efetiva agora é a coluna `effective_at` do próprio `ybira_files`
  # (kernel 0.2): o worker de renditions a preenche com a captura do EXIF,
  # e o `inserted_at` do upload fica como fallback (arquivo sem EXIF, vídeo,
  # worker que não rodou). As duas fontes são colunas do MESMO encoder Ecto
  # (`:utc_datetime`), mas a consulta segue normalizando as duas para UMA
  # representação canônica e ordenável: epoch de segundos. É a mesma chave
  # que o cursor carrega (`epoch|id`), então a virada de página compara
  # inteiro com inteiro, sem depender da codificação do texto no banco.
  # `strftime` do SQLite lê texto sem zona como UTC, o máximo que um EXIF
  # sem timezone permite de qualquer forma (e o `inserted_at` já é UTC).
  # O desempate é o id do arquivo.
  defmacrop effective_ts(f) do
    quote do
      fragment(
        "COALESCE(CAST(strftime('%s', ?) AS INTEGER), CAST(strftime('%s', ?) AS INTEGER))",
        unquote(f).effective_at,
        unquote(f).inserted_at
      )
    end
  end

  defp fetch_timeline_page(%Scope{} = scope, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    base =
      scope
      |> readable_photos()
      |> apply_zona(Keyword.get(opts, :zona))
      |> order_by([f], desc: effective_ts(f), desc: f.id)
      |> select([f], %{file: f, ts: effective_ts(f)})

    rows =
      base
      |> apply_timeline_cursor(decode_timeline_cursor(Keyword.get(opts, :after_cursor)))
      |> limit(^(limit + 1))
      |> Repo.all()

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      {page, encode_timeline_cursor(List.last(page))}
    else
      {rows, nil}
    end
  end

  defp apply_timeline_cursor(query, nil), do: query

  defp apply_timeline_cursor(query, {ts, id}) do
    where(
      query,
      [f],
      effective_ts(f) < ^ts or (effective_ts(f) == ^ts and f.id < ^id)
    )
  end

  defp encode_timeline_cursor(%{ts: epoch, file: %{id: id}}) when is_integer(epoch),
    do: Base.url_encode64("#{epoch}|#{id}", padding: false)

  defp decode_timeline_cursor(nil), do: nil

  defp decode_timeline_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [epoch, id] <- String.split(decoded, "|", parts: 2),
         {ts, ""} <- Integer.parse(epoch),
         {id, ""} <- Integer.parse(id) do
      {ts, id}
    else
      # Cursor ilegível (inclusive o formato ISO8601 anterior à normalização):
      # pagina do começo em vez de quebrar.
      _ -> nil
    end
  end
end
