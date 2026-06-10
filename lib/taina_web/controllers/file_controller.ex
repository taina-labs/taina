defmodule TainaWeb.FileController do
  @moduledoc """
  Download de arquivos do Ybira.

  Autenticação por sessão (cookie do Phoenix): a pipeline `:authenticated` faz
  `fetch_session` e `Maraca.get_session_user/1` resolve o Ava + a Tekoa, de onde
  montamos o `Scope`. O isolamento por Tekoa fica a cargo de `Ybira.get_file/2`.

  Suporta `Range` (RFC 7233): clientes pedem fatias (`Range: bytes=0-1023`) e
  recebem `206 Partial Content`, base para streaming de mídia e retomada de
  download.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira

  def download(conn, %{"public_id" => public_id}) do
    with {:ok, ava} <- Maraca.get_session_user(conn),
         scope = Scope.for_ava(ava),
         {:ok, file} <- Ybira.get_file(scope, public_id) do
      serve_file(conn, file)
    else
      {:error, :not_authenticated} -> send_resp(conn, 401, "")
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  # Tamanhos de thumbnail gerados pelo `Ybira.Workers.Rendition` ("sm" grade,
  # "md" fullscreen). O caminho no disco vem do `metadata` do arquivo; se o job
  # ainda não rodou (ou falhou), respondemos 404 e a UI mostra um placeholder.
  @thumbnail_sizes ~w(sm md)

  def thumbnail(conn, %{"public_id" => public_id, "size" => size}) when size in @thumbnail_sizes do
    with {:ok, ava} <- Maraca.get_session_user(conn),
         scope = Scope.for_ava(ava),
         {:ok, file} <- Ybira.get_file(scope, public_id),
         {:ok, path} <- thumbnail_path(file, size) do
      conn
      |> put_resp_header("content-type", "image/webp")
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_file(200, path)
    else
      {:error, :not_authenticated} -> send_resp(conn, 401, "")
      _ -> send_resp(conn, 404, "")
    end
  end

  def thumbnail(conn, _params), do: send_resp(conn, 404, "")

  defp thumbnail_path(file, size) do
    case get_in(file.metadata, ["thumbnails", size]) do
      path when is_binary(path) ->
        if File.exists?(path), do: {:ok, path}, else: {:error, :not_found}

      _ ->
        {:error, :not_found}
    end
  end

  defp serve_file(conn, file) do
    conn =
      conn
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("content-type", file.mime_type)
      |> put_resp_header("content-disposition", content_disposition(file))
      |> put_last_modified(file)

    case get_req_header(conn, "range") do
      ["bytes=" <> spec] -> serve_range(conn, file, spec)
      _ -> send_file(conn, 200, file.filepath)
    end
  end

  # Tipos seguros de exibir abrem inline (mídia, PDF); o resto baixa como
  # anexo — nada de octet-stream/zip rodando no contexto da página.
  @inline_prefixes ["image/", "video/", "audio/", "application/pdf"]

  defp content_disposition(file) do
    kind = if String.starts_with?(file.mime_type, @inline_prefixes), do: "inline", else: "attachment"
    ~s(#{kind}; filename="#{file.original_filename}")
  end

  # `Last-Modified` ajuda o cache do cliente (revalidação barata em banda
  # limitada). Usa o `updated_at` do registro, que é UTC.
  defp put_last_modified(conn, %{updated_at: %NaiveDateTime{} = at}) do
    httpdate = at |> DateTime.from_naive!("Etc/UTC") |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")
    put_resp_header(conn, "last-modified", httpdate)
  end

  defp put_last_modified(conn, _file), do: conn

  defp serve_range(conn, file, spec) do
    case parse_range(spec, file.file_size_bytes) do
      {:ok, first, last} ->
        conn
        |> put_resp_header(
          "content-range",
          "bytes #{first}-#{last}/#{file.file_size_bytes}"
        )
        |> send_file(206, file.filepath, first, last - first + 1)

      :error ->
        conn
        |> put_resp_header("content-range", "bytes */#{file.file_size_bytes}")
        |> send_resp(416, "")
    end
  end

  # Aceita "first-last", "first-" (até o fim) e "-suffix" (últimos N bytes).
  # Devolve `{:ok, first, last}` com offsets inclusivos e dentro de [0, total).
  defp parse_range(spec, total) do
    case String.split(spec, "-", parts: 2) do
      ["", suffix] -> suffix_range(suffix, total)
      [first, ""] -> open_range(first, total)
      [first, last] -> closed_range(first, last, total)
      _ -> :error
    end
  end

  defp suffix_range(suffix, total) do
    case Integer.parse(suffix) do
      {len, ""} when len > 0 and total > 0 ->
        first = max(total - len, 0)
        {:ok, first, total - 1}

      _ ->
        :error
    end
  end

  defp open_range(first, total) do
    case Integer.parse(first) do
      {first, ""} when first >= 0 and first < total -> {:ok, first, total - 1}
      _ -> :error
    end
  end

  defp closed_range(first, last, total) do
    with {first, ""} when first >= 0 <- Integer.parse(first),
         {last, ""} when last >= first <- Integer.parse(last),
         true <- first < total do
      {:ok, first, min(last, total - 1)}
    else
      _ -> :error
    end
  end
end
