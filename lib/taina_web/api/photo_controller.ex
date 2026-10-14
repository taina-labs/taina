defmodule TainaWeb.API.PhotoController do
  @moduledoc """
  As fotos e videos legiveis (RFC_005 secao 9): a grade e a linha do tempo,
  ambas paginadas por keyset.
  """

  use TainaWeb, :controller

  alias Taina.Jaci
  alias TainaWeb.API.Error
  alias TainaWeb.API.Query
  alias Ypy.Wire

  def index(conn, params) do
    opts = [limit: Query.limit(params), after_cursor: Query.cursor(params)]

    case Jaci.list_photos(conn.assigns[:current_scope], opts) do
      {:ok, %{items: items, next_cursor: next}} ->
        json(conn, Wire.page(Enum.map(items, &Wire.File.json/1), next))

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end

  def timeline(conn, params) do
    opts = [limit: Query.limit(params), after_cursor: Query.cursor(params)]

    case Jaci.timeline(conn.assigns[:current_scope], opts) do
      {:ok, %{groups: groups, next_cursor: next}} ->
        json(conn, Wire.page(Enum.map(groups, &group_json/1), next))

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end

  # A linha do tempo agrupa por dia: o item e o dia, com as fotos dentro.
  defp group_json(%{date: %Date{} = date, photos: photos}) do
    %{"date" => Date.to_iso8601(date), "photos" => Enum.map(photos, &Wire.File.json/1)}
  end
end
