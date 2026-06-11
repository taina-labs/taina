defmodule Taina.Jaci do
  @moduledoc """
  Jaci-lite — a galeria de fotos da comunidade.

  Implementa `Taina.Jaci.Behaviour`; as regras de negócio estão lá, nos
  `@callback`. Jaci é uma camada de **leitura** sobre o Ybira (RFC 002, D4):
  consulta os arquivos de imagem (`mime_type image/*`) que o Ybira guarda e os
  apresenta como grade (`list_photos/2`) e linha do tempo (`timeline/2`). Não
  grava nem muta nada — upload, thumbnail e soft delete são do Ybira.

  Como todo context, recebe um `Taina.Scope` e roda dentro de
  `Repo.with_tekoa/2` (isolamento RLS). A paginação segue o keyset do Ybira: a
  grade ordena por upload (`id` decrescente basta, pois é serial monótono); a
  linha do tempo ordena pela data efetiva da foto (EXIF ou upload), exigindo um
  cursor composto `(data, id)`.
  """

  @behaviour Taina.Jaci.Behaviour

  import Ecto.Query

  alias Taina.Jaci.Timeline
  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira.File, as: YbiraFile

  @default_limit 50

  # Expressão SQL da data efetiva: captura do EXIF quando houver, senão upload.
  # Espelha `Timeline.effective_datetime/1` e o índice de
  # `*_jaci_photo_indexes` — os três precisam concordar.
  defmacrop effective_ts(file) do
    quote do
      fragment("COALESCE((? ->> 'taken_at')::timestamp, ?)", unquote(file).metadata, unquote(file).inserted_at)
    end
  end

  @impl true
  def list_photos(%Scope{} = scope, opts \\ []) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      query =
        from f in YbiraFile,
          where: is_nil(f.deleted_at) and like(f.mime_type, "image/%"),
          # id serial monótono = ordem de upload; alinha com o cursor (id-only).
          order_by: [desc: f.id]

      {items, next_cursor} = fetch_grid_page(query, opts)
      {:ok, %{items: items, next_cursor: next_cursor}}
    end)
  end

  @impl true
  def timeline(%Scope{} = scope, opts \\ []) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      {photos, next_cursor} = fetch_timeline_page(opts)
      {:ok, %{groups: Timeline.group_by_date(photos), next_cursor: next_cursor}}
    end)
  end

  # --- Grade: keyset por id (alinhado ao upload) ---

  defp fetch_grid_page(query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    rows =
      query
      |> apply_id_cursor(Keyword.get(opts, :after_cursor))
      |> limit(^(limit + 1))
      |> Repo.all()

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      {page, encode_id_cursor(List.last(page))}
    else
      {rows, nil}
    end
  end

  defp apply_id_cursor(query, nil), do: query

  defp apply_id_cursor(query, cursor) when is_binary(cursor) do
    case Base.url_decode64(cursor, padding: false) do
      {:ok, <<id::64>>} -> where(query, [f], f.id < ^id)
      _ -> query
    end
  end

  defp encode_id_cursor(%{id: id}), do: Base.url_encode64(<<id::64>>, padding: false)

  # --- Linha do tempo: keyset composto (data efetiva, id) ---

  defp fetch_timeline_page(opts) do
    limit = Keyword.get(opts, :limit, @default_limit)

    base =
      from f in YbiraFile,
        where: is_nil(f.deleted_at) and like(f.mime_type, "image/%"),
        order_by: [desc: effective_ts(f), desc: f.id],
        select: %{file: f, ts: effective_ts(f)}

    rows =
      base
      |> apply_timeline_cursor(decode_timeline_cursor(Keyword.get(opts, :after_cursor)))
      |> limit(^(limit + 1))
      |> Repo.all()

    if length(rows) > limit do
      page = Enum.take(rows, limit)
      last = List.last(page)
      {Enum.map(page, & &1.file), encode_timeline_cursor(last)}
    else
      {Enum.map(rows, & &1.file), nil}
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

  defp encode_timeline_cursor(%{ts: %NaiveDateTime{} = ts, file: %{id: id}}) do
    Base.url_encode64("#{NaiveDateTime.to_iso8601(ts)}|#{id}", padding: false)
  end

  defp decode_timeline_cursor(nil), do: nil

  defp decode_timeline_cursor(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [iso, id] <- String.split(decoded, "|", parts: 2),
         {:ok, ts} <- NaiveDateTime.from_iso8601(iso),
         {id, ""} <- Integer.parse(id) do
      {ts, id}
    else
      _ -> nil
    end
  end
end
