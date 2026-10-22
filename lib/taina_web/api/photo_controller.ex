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
      json(conn, Wire.page(Enum.map(items, &Serializer.file(scope, &1)), next))
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
      json(conn, Wire.page(Enum.map(groups, &group_json(scope, &1)), next))
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # A linha do tempo agrupa por dia: o item e o dia, com as fotos dentro.
  defp group_json(scope, %{date: %Date{} = date, photos: photos}) do
    %{
      "date" => Date.to_iso8601(date),
      "photos" => Enum.map(photos, &Serializer.file(scope, &1))
    }
  end
end
