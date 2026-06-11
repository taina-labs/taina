defmodule Taina.Ybira.Media do
  @moduledoc """
  Processamento de imagem do Ybira — o único lugar que fala com a libvips
  (via `image`/`vix`). Isolar aqui mantém a dependência de mídia numa fronteira
  fina: o resto do código pede dimensões, data de captura e thumbnails sem saber
  qual biblioteca está por baixo.

  Tudo é *best-effort* (RFC 002, D8): HEIC e arquivos corrompidos podem falhar
  na leitura sem derrubar o upload — quem chama trata o `{:error, _}` e segue.
  A detecção de tipo já aconteceu no upload (magic bytes); aqui assumimos um
  arquivo de imagem plausível.
  """

  # Formato de data/hora do EXIF: "2023:07:15 14:30:00" (sem timezone).
  @exif_datetime ~r/^\d{4}:\d{2}:\d{2} \d{2}:\d{2}:\d{2}$/

  @doc """
  Lê metadados leves de uma imagem: dimensões e, quando houver, a data de
  captura do EXIF (`taken_at`, `NaiveDateTime` — o EXIF não carrega timezone).

  Retorna `{:ok, %{width, height, taken_at}}` ou `{:error, term}`.
  """
  @spec analyze(Path.t()) ::
          {:ok, %{width: pos_integer, height: pos_integer, taken_at: NaiveDateTime.t() | nil}} | {:error, term}
  def analyze(path) do
    with {:ok, image} <- Image.open(path) do
      {:ok,
       %{
         width: Image.width(image),
         height: Image.height(image),
         taken_at: taken_at(image)
       }}
    end
  rescue
    e -> {:error, e}
  end

  @doc """
  Gera um thumbnail de `src` em `dest` (WebP) com a maior aresta limitada a
  `max_edge` px. Usa o *shrink-on-load* da libvips a partir do caminho, então é
  rápido e econômico de memória mesmo em ARM. Cria o diretório de destino.

  Retorna `:ok` ou `{:error, term}`.
  """
  @spec thumbnail(Path.t(), Path.t(), pos_integer) :: :ok | {:error, term}
  def thumbnail(src, dest, max_edge) when is_integer(max_edge) and max_edge > 0 do
    with :ok <- File.mkdir_p(Path.dirname(dest)),
         {:ok, thumb} <- Image.thumbnail(src, max_edge),
         {:ok, _} <- Image.write(thumb, dest, quality: 80) do
      :ok
    end
  rescue
    e -> {:error, e}
  end

  # --- EXIF ---

  defp taken_at(image) do
    with {:ok, exif} <- Image.exif(image),
         {_key, value} <- find_exif_datetime(exif),
         %NaiveDateTime{} = dt <- parse_exif_datetime(value) do
      dt
    else
      _ -> nil
    end
  end

  # O `image` aninha o EXIF em sub-mapas cujas chaves variam entre versões e
  # câmeras. Em vez de acoplar a chaves específicas, varremos os valores
  # procurando o formato de data/hora do EXIF e preferimos a chave "original"
  # (DateTimeOriginal — o instante da captura, não o da última edição).
  defp find_exif_datetime(exif) do
    exif
    |> collect_datetimes([])
    |> Enum.sort_by(fn {key, _} -> if String.contains?(key, "original"), do: 0, else: 1 end)
    |> List.first()
  end

  defp collect_datetimes(map, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {key, value}, acc ->
      cond do
        is_map(value) -> collect_datetimes(value, acc)
        is_binary(value) and Regex.match?(@exif_datetime, value) -> [{downcase(key), value} | acc]
        true -> acc
      end
    end)
  end

  defp collect_datetimes(_other, acc), do: acc

  defp downcase(key) when is_atom(key), do: key |> Atom.to_string() |> String.downcase()
  defp downcase(key) when is_binary(key), do: String.downcase(key)

  defp parse_exif_datetime(<<y::binary-4, ":", mo::binary-2, ":", d::binary-2, " ", time::binary>>) do
    case NaiveDateTime.from_iso8601("#{y}-#{mo}-#{d}T#{time}") do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp parse_exif_datetime(_other), do: nil
end
