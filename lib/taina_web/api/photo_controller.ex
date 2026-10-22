defmodule TainaWeb.API.PhotoController do
  @moduledoc """
  As fotos e videos legiveis (RFC_005 secao 9): a grade e a linha do tempo,
  ambas paginadas por keyset. O ETag cobre o conjunto legivel inteiro.
  """

  use TainaWeb, :controller

  alias Taina.Jaci
  alias TainaWeb.API.Error
  alias TainaWeb.API.Etag
  alias TainaWeb.API.Query
  alias TainaWeb.API.Serializer
  alias Ypy.Wire

  def index(conn, params) do
    scope = conn.assigns[:current_scope]
    opts = [limit: Query.limit(params), after_cursor: Query.cursor(params)]

    with {:fresh, conn} <- Etag.handle(conn, Etag.photos(scope)),
         {:ok, %{items: items, next_cursor: next}} <- Jaci.list_photos(scope, opts) do
      json(conn, Wire.page(Serializer.files(scope, items), next))
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def timeline(conn, params) do
    scope = conn.assigns[:current_scope]
    opts = [limit: Query.limit(params), after_cursor: Query.cursor(params)]

    with {:fresh, conn} <- Etag.handle(conn, Etag.photos(scope)),
         {:ok, %{groups: groups, next_cursor: next}} <- Jaci.timeline(scope, opts) do
      json(conn, Wire.page(timeline_json(scope, groups), next))
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # A linha do tempo agrupa por dia: o item e o dia, com as fotos dentro. As
  # fotos da pagina inteira saem em serie pelo lote do serializer, e cada
  # dia busca as suas no mapa (o rkey e unico).
  defp timeline_json(scope, groups) do
    flat = Enum.flat_map(groups, & &1.photos)

    by_rkey =
      flat
      |> Enum.zip(Serializer.files(scope, flat))
      |> Map.new(fn {file, json} -> {file.rkey, json} end)

    for %{date: %Date{} = date, photos: photos} <- groups do
      %{"date" => Date.to_iso8601(date), "photos" => Enum.map(photos, &Map.fetch!(by_rkey, &1.rkey))}
    end
  end
end
