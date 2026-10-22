defmodule TainaWeb.API.TrashController do
  @moduledoc """
  A lixeira da propria pessoa (RFC_005 secao 9): listar e restaurar. So a dona
  ve o proprio lixo, nem o kernel lista o dos outros.
  """

  use TainaWeb, :controller

  alias Taina.Ybira
  alias TainaWeb.API.Error
  alias TainaWeb.API.Etag
  alias TainaWeb.API.Query
  alias TainaWeb.API.Serializer
  alias Ypy.Wire

  def index(conn, params) do
    scope = conn.assigns[:current_scope]
    opts = [limit: Query.limit(params), after_cursor: Query.cursor(params)]

    with {:fresh, conn} <- Etag.handle(conn, Etag.trash(scope)),
         {:ok, %{items: items, next_cursor: next}} <- Ybira.list_trash(scope, opts) do
      json(conn, Wire.page(Enum.map(items, &Serializer.file(scope, &1)), next))
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def restore(conn, %{"file_id" => rkey}) do
    scope = conn.assigns[:current_scope]

    case Ybira.restore_file(scope, rkey) do
      {:ok, file} -> json(conn, Serializer.file(scope, file))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end
end
