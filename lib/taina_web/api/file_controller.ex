defmodule TainaWeb.API.FileController do
  @moduledoc """
  Arquivos pela API (RFC_005 secao 9): upload multipart, metadado, download e
  miniatura.

  O upload reusa `Ybira.upload/3` (cota, MIME por magic bytes, limpeza em erro);
  os bytes saem pelo mesmo `TainaWeb.FileServing` da web, sob a regra de leitura
  das duas zonas.
  """

  use TainaWeb, :controller

  alias Taina.Ybira
  alias TainaWeb.API.Error
  alias TainaWeb.API.Query
  alias TainaWeb.FileServing
  alias Ypy.Wire

  def create(conn, params) do
    scope = conn.assigns[:current_scope]

    case upload_params(params) do
      {:ok, tmp_path, opts} ->
        case Ybira.upload(scope, tmp_path, opts) do
          {:ok, file} -> conn |> put_status(201) |> json(file_json(scope, file))
          {:error, reason} -> Error.reply(conn, reason)
        end

      :error ->
        Error.reply(conn, :missing_file)
    end
  end

  def show(conn, %{"id" => rkey}) do
    scope = conn.assigns[:current_scope]

    case Ybira.get_file(scope, rkey) do
      {:ok, file} -> json(conn, file_json(scope, file))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def download(conn, %{"id" => rkey}) do
    with {:ok, file} <- Ybira.get_file(conn.assigns[:current_scope], rkey),
         {:ok, path} <- Ybira.blob_path(file) do
      FileServing.serve(conn, file, path)
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def thumbnail(conn, %{"id" => rkey, "size" => size}) do
    scope = conn.assigns[:current_scope]

    with {:ok, file} <- Ybira.get_file(scope, rkey),
         {:ok, metadata} <- Ybira.photo_metadata(scope, file) do
      # Sem rendition e caso normal, nao falha de servidor: a API responde o
      # envelope (404 not_found), que e onde o cliente le o code. A web segue
      # com o 404 seco do `FileServing`, que e o que um `<img>` precisa.
      if FileServing.thumbnail?(metadata, size) do
        FileServing.thumbnail(conn, metadata, size)
      else
        Error.reply(conn, :not_found)
      end
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def recent(conn, params) do
    case Ybira.list_recent(conn.assigns[:current_scope], limit: Query.limit(params)) do
      {:ok, files} -> json(conn, Wire.page(Enum.map(files, &Wire.File.json/1), nil))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def update(conn, %{"id" => rkey} = params) do
    scope = conn.assigns[:current_scope]

    case change(scope, rkey, params) do
      {:ok, file} -> json(conn, file_json(scope, file))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def move(conn, %{"id" => rkey} = params) do
    scope = conn.assigns[:current_scope]

    case Ybira.move_file(scope, rkey, params["folder"]) do
      {:ok, file} -> json(conn, file_json(scope, file))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def delete(conn, %{"id" => rkey}) do
    case Ybira.delete_file(conn.assigns[:current_scope], rkey) do
      {:ok, _file} -> send_resp(conn, 204, "")
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # Renomear ou trocar de zona; a zona e um ato proprio (publicar/tirar).
  defp change(scope, rkey, params) do
    cond do
      is_binary(params["name"]) -> Ybira.rename_file(scope, rkey, params["name"])
      params["zona"] == "praca" -> Ybira.publicar_file(scope, rkey)
      params["zona"] == "casa" -> Ybira.tirar_file_da_praca(scope, rkey)
      true -> {:error, :invalid_action}
    end
  end

  defp upload_params(%{"file" => %Plug.Upload{path: path, filename: filename}} = params) do
    opts = [filename: filename]

    case params["folder"] do
      folder when is_binary(folder) and folder != "" -> {:ok, path, Keyword.put(opts, :folder_rkey, folder)}
      _ -> {:ok, path, opts}
    end
  end

  defp upload_params(_params), do: :error

  # A pasta pai do arquivo: o shape do kernel so a traz quando veio preload, e
  # a regra de leitura (a mesma que autoriza a leitura) resolve o rkey dela.
  defp file_json(scope, file) do
    case Ybira.file_folder_rkey(scope, file) do
      {:ok, folder_rkey} -> Map.put(Wire.File.json(file), "folder", folder_rkey)
      _ -> Wire.File.json(file)
    end
  end
end
