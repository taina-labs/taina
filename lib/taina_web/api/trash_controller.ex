defmodule TainaWeb.API.TrashController do
  @moduledoc """
  A lixeira da propria pessoa (RFC_005 secao 9): listar e restaurar. So a dona
  ve o proprio lixo, nem o kernel lista o dos outros.
  """

  use TainaWeb, :controller

  alias Taina.Ybira
  alias TainaWeb.API.Error
  alias TainaWeb.API.Query
  alias Ypy.Wire

  def index(conn, params) do
    opts = [limit: Query.limit(params), after_cursor: Query.cursor(params)]

    case Ybira.list_trash(conn.assigns[:current_scope], opts) do
      {:ok, %{items: items, next_cursor: next}} ->
        json(conn, Wire.page(Enum.map(items, &Wire.File.json/1), next))

      {:error, reason} ->
        Error.reply(conn, reason)
    end
  end

  def restore(conn, %{"file_id" => rkey}) do
    case Ybira.restore_file(conn.assigns[:current_scope], rkey) do
      {:ok, file} -> json(conn, Wire.File.json(file))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end
end
