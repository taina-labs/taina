defmodule TainaWeb.FileServing do
  @moduledoc """
  Os bytes do Ybira no fio (RFC_005 secao 8): a web (sessao de cookie) e a API
  (Bearer) compartilham o mesmo servico de download e miniatura.

  O modulo so escreve a resposta: quem autoriza e resolve o arquivo sao as
  frentes, que nunca abrem um arquivo sozinhas. A regra das duas zonas vale nas
  duas porque as duas chamam `Ybira.get_file/2` antes de servir byte.
  """

  import Plug.Conn

  @thumbnail_sizes ~w(sm md)

  # Tipos seguros de exibir abrem inline (midia, PDF); o resto baixa como
  # anexo, nada de octet-stream/zip rodando no contexto da pagina.
  @inline_prefixes ["image/", "video/", "audio/", "application/pdf"]

  @doc ~s{Os tamanhos de miniatura que a rendition gera ("sm" grade, "md" tela cheia).}
  def thumbnail_sizes, do: @thumbnail_sizes

  @doc """
  Serve o arquivo, com `Range` (RFC 7233): o cliente que pede fatia recebe 206
  `Partial Content`, base para streaming e retomada de download.
  """
  def serve(conn, file, path) do
    conn =
      conn
      |> put_resp_header("accept-ranges", "bytes")
      |> put_resp_header("content-type", file.mime)
      |> put_resp_header("content-disposition", content_disposition(file))
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_last_modified(file)

    case get_req_header(conn, "range") do
      ["bytes=" <> spec] -> serve_range(conn, file, path, spec)
      _ -> send_file(conn, 200, path)
    end
  end

  @doc """
  Se a miniatura do tamanho existe no disco. A web responde 404 seco, que e o
  que um `<img>` precisa; a API responde o envelope, que e o contrato do
  cliente, entao ela pergunta antes.
  """
  @spec thumbnail?(map(), String.t()) :: boolean()
  def thumbnail?(metadata, size), do: match?({:ok, _}, thumbnail_path(metadata, size))

  @doc """
  Serve a miniatura webp a partir dos metadados de rendicao do produto. Tamanho
  desconhecido ou ainda nao gerado (job falhou, imagem sem rendition) responde
  404, e a UI mostra o placeholder.
  """
  def thumbnail(conn, metadata, size) when size in @thumbnail_sizes do
    case thumbnail_path(metadata, size) do
      {:ok, path} ->
        conn
        |> put_resp_header("content-type", "image/webp")
        |> put_resp_header("cache-control", "private, max-age=86400")
        |> send_file(200, path)

      {:error, :not_found} ->
        send_resp(conn, 404, "")
    end
  end

  def thumbnail(conn, _metadata, _size), do: send_resp(conn, 404, "")

  defp thumbnail_path(metadata, size) do
    case get_in(metadata, ["thumbnails", size]) do
      path when is_binary(path) ->
        if File.exists?(path), do: {:ok, path}, else: {:error, :not_found}

      _ ->
        {:error, :not_found}
    end
  end

  # O nome vem do cliente: o `filename` fica ASCII e sem aspas/barra (nao quebra
  # o parametro) e a versao fiel vai percent-encoded em `filename*` (RFC 5987).
  defp content_disposition(file) do
    kind = if String.starts_with?(file.mime, @inline_prefixes), do: "inline", else: "attachment"
    ascii = String.replace(file.nome, ~r/[^\x20-\x7E]|["\\]/, "_")
    encoded = URI.encode(file.nome, &URI.char_unreserved?/1)
    ~s(#{kind}; filename="#{ascii}"; filename*=UTF-8''#{encoded})
  end

  # `Last-Modified` ajuda o cache do cliente (revalidacao barata em banda
  # limitada). Usa o `updated_at` do registro, que e UTC.
  defp put_last_modified(conn, %{updated_at: %DateTime{} = at}) do
    put_resp_header(conn, "last-modified", Calendar.strftime(at, "%a, %d %b %Y %H:%M:%S GMT"))
  end

  defp put_last_modified(conn, _file), do: conn

  defp serve_range(conn, file, path, spec) do
    case parse_range(spec, file.tamanho) do
      {:ok, first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{file.tamanho}")
        |> send_file(206, path, first, last - first + 1)

      :error ->
        conn
        |> put_resp_header("content-range", "bytes */#{file.tamanho}")
        |> send_resp(416, "")
    end
  end

  # Aceita "first-last", "first-" (ate o fim) e "-suffix" (ultimos N bytes).
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
