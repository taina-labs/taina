defmodule TainaWeb.API.MuralController do
  @moduledoc """
  O mural (RFC_005 secao 9): a projecao legivel da cadeia, da entrada mais
  recente para a mais antiga, paginada por offset.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias TainaWeb.API.Error
  alias TainaWeb.API.Query
  alias Ypy.Wire

  def index(conn, params) do
    opts = [limit: Query.limit(params), offset: Query.offset(params)]

    case Maraca.list_events(conn.assigns[:current_scope], opts) do
      {:ok, %{events: events, next_offset: next}} ->
        json(conn, Wire.page(Enum.map(events, &Wire.Mural.json/1), Query.encode_offset(next)))

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end
end
