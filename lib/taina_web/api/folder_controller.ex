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
    scope = conn.assigns[:current_scope]

    case Ybira.list_folders(scope) do
      {:ok, folders} -> json(conn, Wire.page(Serializer.folders(scope, folders), nil))
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
      {:ok, folder} ->
        conn
        |> put_status(201)
        |> json(folder_json(scope, folder, params["parent_rkey"]))

      {:error, reason} ->
        Error.reply(conn, reason)
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
          Enum.map(folders, &folder_json(scope, &1, params["folder"])),
          Serializer.files(scope, files),
          Query.encode_offset(next)
        )
      )
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # A pasta no fio do produto (Serializer.folder, dono resolvido); o pai vem
  # do parametro quando a rota o conhece (o conteudo de uma pasta).
  defp folder_json(scope, folder, nil), do: Serializer.folder(scope, folder)

  defp folder_json(scope, folder, parent_rkey), do: Map.put(Serializer.folder(scope, folder), "folder", parent_rkey)

  # O pai de uma pasta sozinha: o penultimo elo do breadcrumb (raiz -> atual).
  defp resolved_folder_json(scope, folder) do
    case Ybira.folder_path(scope, folder.rkey) do
      {:ok, path} when length(path) > 1 ->
        Map.put(Serializer.folder(scope, folder), "folder", Enum.at(path, -2).rkey)

      _ ->
        Serializer.folder(scope, folder)
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
