defmodule TainaWeb.API.FileController do
  @moduledoc """
  Arquivos pela API (RFC_005 secao 9): upload multipart, metadado, download,
  miniatura, manifesto de backup e operacoes em lote.

  O upload reusa `Ybira.upload/3` (cota, MIME por magic bytes, limpeza em erro);
  os bytes saem pelo mesmo `TainaWeb.FileServing` da web, sob a regra de leitura
  das duas zonas. O manifesto e as rendicoes de miniatura tem codigos proprios
  no fio (contrato review 0.1.0, A/B/C).
  """

  use TainaWeb, :controller

  alias Taina.Ybira
  alias Taina.Ybira.Manifest
  alias Taina.Ybira.RenditionStatus
  alias TainaWeb.API.Error
  alias TainaWeb.API.Etag
  alias TainaWeb.API.Query
  alias TainaWeb.API.Serializer
  alias TainaWeb.FileServing
  alias Ypy.Wire

  @batch_max_ids 200

  def create(conn, params) do
    scope = conn.assigns[:current_scope]

    case upload_params(params) do
      {:ok, tmp_path, opts} ->
        case Ybira.upload(scope, tmp_path, opts) do
          {:ok, file} -> conn |> put_status(201) |> json(Serializer.file(scope, file))
          {:error, reason} -> Error.reply(conn, reason)
        end

      :error ->
        Error.reply(conn, :missing_file)
    end
  end

  def show(conn, %{"id" => rkey}) do
    scope = conn.assigns[:current_scope]

    case Ybira.get_file(scope, rkey) do
      {:ok, file} -> json(conn, Serializer.file(scope, file))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # O manifesto de backup: todo arquivo legivel, do mais antigo para o mais
  # novo, um sha256 por linha. O ETag e do conjunto inteiro, e a pagina so
  # sai quando ele nao bate com o If-None-Match.
  def manifest(conn, params) do
    scope = conn.assigns[:current_scope]
    opts = [limit: Query.limit(params, default: 200, max: 1000), after: Query.after_cursor(params)]

    with {:fresh, conn} <- Etag.handle(conn, Etag.readable_files(scope)),
         {:ok, %{items: files, next_cursor: next}} <- Manifest.page(scope, opts) do
      json(conn, Wire.page(Enum.map(files, &Serializer.file(scope, &1)), next))
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  # O lote corre item a item pelo mesmo contexto do endpoint unitario; a
  # falha de um nao para os outros (200 com o resultado de cada um).
  def batch(conn, params) do
    scope = conn.assigns[:current_scope]

    case batch_params(params) do
      {:ok, op, ids, folder} ->
        results = Enum.map(ids, &run(scope, op, &1, folder))
        json(conn, %{"results" => results})

      # O vocabulario do fio nao tem o atomo (changeset e que vira
      # validation_failed); a borda do lote responde ele direto, 422.
      {:error, :validation_failed} ->
        Error.reply(conn, 422, "validation_failed")

      {:error, reason} ->
        Error.reply(conn, reason)
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
      serve_thumbnail(conn, scope, file, metadata, size)
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def recent(conn, params) do
    scope = conn.assigns[:current_scope]

    with {:fresh, conn} <- Etag.handle(conn, Etag.readable_files(scope)),
         {:ok, files} <- Ybira.list_recent(scope, limit: Query.limit(params)) do
      json(conn, Wire.page(Enum.map(files, &Serializer.file(scope, &1)), nil))
    else
      {:not_modified, conn} -> conn
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def update(conn, %{"id" => rkey} = params) do
    scope = conn.assigns[:current_scope]

    case change(scope, rkey, params) do
      {:ok, file} -> json(conn, Serializer.file(scope, file))
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def move(conn, %{"id" => rkey} = params) do
    scope = conn.assigns[:current_scope]

    case Ybira.move_file(scope, rkey, params["folder"]) do
      {:ok, file} -> json(conn, Serializer.file(scope, file))
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

  ## Lote (contrato review 0.1.0, C2)

  defp batch_params(params) do
    with {:ok, op} <- parse_op(params["op"]),
         {:ok, ids} <- parse_ids(params["ids"]) do
      {:ok, op, ids, params["folder"]}
    end
  end

  defp parse_op("trash"), do: {:ok, :trash}
  defp parse_op("restore"), do: {:ok, :restore}
  defp parse_op("move"), do: {:ok, :move}
  defp parse_op("publish"), do: {:ok, :publish}
  defp parse_op("unpublish"), do: {:ok, :unpublish}
  defp parse_op(_op), do: {:error, :invalid_action}

  defp parse_ids(ids) when is_list(ids) do
    if Enum.all?(ids, &is_binary/1) and length(ids) <= @batch_max_ids,
      do: {:ok, ids},
      else: {:error, :validation_failed}
  end

  defp parse_ids(_ids), do: {:error, :validation_failed}

  defp run(scope, op, rkey, folder) do
    case apply_op(scope, op, rkey, folder) do
      {:ok, file} -> %{"rkey" => rkey, "ok" => true, "file" => Serializer.file(scope, file)}
      {:error, reason} -> %{"rkey" => rkey, "ok" => false, "error" => code(reason)}
    end
  end

  # O destino do `move` e o rkey da pasta (ou nil, para a raiz); nos outros
  # verbos a pasta nao significa nada.
  defp apply_op(scope, :trash, rkey, _folder), do: Ybira.delete_file(scope, rkey)
  defp apply_op(scope, :restore, rkey, _folder), do: Ybira.restore_file(scope, rkey)
  defp apply_op(scope, :move, rkey, folder), do: Ybira.move_file(scope, rkey, folder)
  defp apply_op(scope, :publish, rkey, _folder), do: Ybira.publicar_file(scope, rkey)
  defp apply_op(scope, :unpublish, rkey, _folder), do: Ybira.tirar_file_da_praca(scope, rkey)

  # O code do item e o vocabulario estavel: o motivo do contexto em string.
  defp code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp code(%Ecto.Changeset{}), do: "validation_failed"
  defp code(_reason), do: "internal_error"

  ## Miniatura (contrato review 0.1.0, B)

  # Pendente e falha sao 404s distintos no envelope, para o cliente nao
  # confundir "ainda vai ter" com "nunca vai ter". Nao-imagem e tamanho que
  # nao existe ficam no 404 not_found de sempre.
  defp serve_thumbnail(conn, scope, file, metadata, size) do
    case RenditionStatus.status(scope, file) do
      :ready ->
        if FileServing.thumbnail?(metadata, size) do
          FileServing.thumbnail(conn, metadata, size)
        else
          Error.reply(conn, :not_found)
        end

      :pending ->
        Error.reply(conn, :rendition_pending)

      :unavailable ->
        Error.reply(conn, :rendition_unavailable)

      :none ->
        Error.reply(conn, :not_found)
    end
  end
end
