defmodule TainaWeb.API.FolderController do
  @moduledoc """
  Pastas pela API (RFC_005 secao 9): a lista, a criacao e o conteudo de uma
  pasta (pastas completas, arquivos paginados).
  """

  use TainaWeb, :controller

  alias Taina.Ybira
  alias TainaWeb.API.Error
  alias TainaWeb.API.Etag
  alias TainaWeb.API.Query
  alias TainaWeb.API.Serializer
  alias Ypy.Wire

  def index(conn, _params) do
    case Ybira.list_folders(conn.assigns[:current_scope]) do
      {:ok, folders} -> json(conn, Wire.page(Enum.map(folders, &Wire.File.json/1), nil))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def show(conn, %{"id" => rkey}) do
    scope = conn.assigns[:current_scope]

    case Ybira.get_folder(scope, rkey) do
      {:ok, folder} -> json(conn, resolved_folder_json(scope, folder))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def create(conn, params) do
    scope = conn.assigns[:current_scope]
    attrs = %{name: params["name"], parent_rkey: params["parent_rkey"]}

    case Ybira.create_folder(scope, attrs) do
      {:ok, folder} -> conn |> put_status(201) |> json(folder_json(folder, params["parent_rkey"]))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def contents(conn, params) do
    scope = conn.assigns[:current_scope]
    opts = maybe_sort([limit: Query.limit(params), offset: Query.offset(params)], params)

    with {:ok, etag} <- Etag.folder_files(scope, params["folder"]),
         {:fresh, conn} <- Etag.handle(conn, etag),
         {:ok, %{folders: folders, files: files, next_cursor: next}} <-
           Ybira.list_folder_contents(scope, params["folder"], opts) do
      json(
        conn,
        Wire.folder_page(
          Enum.map(folders, &folder_json(&1, params["folder"])),
          Enum.map(files, &Serializer.file(scope, &1)),
          Query.encode_offset(next)
        )
      )
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  defp folder_json(folder, nil), do: Wire.File.json(folder)

  defp folder_json(folder, parent_rkey), do: Map.put(Wire.File.json(folder), "folder", parent_rkey)

  # O pai de uma pasta sozinha: o penultimo elo do breadcrumb (raiz -> atual).
  defp resolved_folder_json(scope, folder) do
    case Ybira.folder_path(scope, folder.rkey) do
      {:ok, path} when length(path) > 1 ->
        Map.put(Wire.File.json(folder), "folder", Enum.at(path, -2).rkey)

      _ ->
        Wire.File.json(folder)
    end
  end

  def update(conn, %{"id" => rkey} = params) do
    scope = conn.assigns[:current_scope]

    case change(scope, rkey, params) do
      {:ok, folder} -> json(conn, resolved_folder_json(scope, folder))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def move(conn, %{"id" => rkey} = params) do
    scope = conn.assigns[:current_scope]

    case Ybira.move_folder(scope, rkey, params["parent_rkey"]) do
      {:ok, folder} -> json(conn, resolved_folder_json(scope, folder))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def delete(conn, %{"id" => rkey}) do
    case Ybira.delete_folder(conn.assigns[:current_scope], rkey) do
      {:ok, _deleted} -> send_resp(conn, 204, "")
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # Renomear ou trocar de zona; a zona e um ato proprio (publicar/tirar).
  defp change(scope, rkey, params) do
    cond do
      is_binary(params["name"]) -> Ybira.rename_folder(scope, rkey, params["name"])
      params["zona"] == "praca" -> Ybira.publicar_folder(scope, rkey)
      params["zona"] == "casa" -> Ybira.tirar_folder_da_praca(scope, rkey)
      true -> {:error, :invalid_action}
    end
  end

  defp maybe_sort(opts, params) do
    case Query.sort(params) do
      nil -> opts
      sort -> Keyword.put(opts, :sort, sort)
    end
  end
end
