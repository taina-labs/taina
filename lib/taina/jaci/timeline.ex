defmodule Taina.Jaci.Timeline do
  @moduledoc """
  Núcleo puro da linha do tempo do Jaci. Sem banco, sem efeito colateral: só
  agrupa uma lista já ordenada em baldes por dia.

  A data efetiva de uma foto é a captura do EXIF (`metadata["taken_at"]` das
  rendições do produto) quando existe; senão, o instante do upload
  (`inserted_at`), o "mtime" da RFC 002, Fase 3. A resolução acontece na
  consulta (`Taina.Jaci`, `COALESCE`); daqui em diante a data já vem na linha.
  O EXIF não carrega timezone, então trabalhamos em `NaiveDateTime`.
  """

  alias Ypy.Ybira.File

  @typedoc "Um dia da linha do tempo: a data e as fotos daquele dia, mais novas primeiro."
  @type group :: %{date: Date.t(), photos: [File.t()]}

  @doc """
  Agrupa linhas **já ordenadas por data efetiva decrescente** (`%{file:, ts:}`,
  a data resolvida na consulta) em baldes diários consecutivos. Como a entrada
  vem ordenada, todas as fotos de um mesmo dia são contíguas, `chunk_by` basta.
  Em paginação, um dia pode se repartir entre o fim de uma página e o início da
  próxima; a UI funde grupos de mesma data adjacentes.
  """
  @spec group_by_date([%{file: File.t(), ts: term()}]) :: [group()]
  def group_by_date(rows) do
    rows
    |> Enum.chunk_by(&date_of/1)
    |> Enum.map(fn [first | _] = chunk ->
      %{date: date_of(first), photos: Enum.map(chunk, & &1.file)}
    end)
  end

  defp date_of(%{ts: %NaiveDateTime{} = ts}), do: NaiveDateTime.to_date(ts)
  defp date_of(%{ts: %DateTime{} = ts}), do: DateTime.to_date(ts)
  # O SQLite devolve o `taken_at` do JSON como texto ISO8601; a ordenação casa
  # com o `inserted_at` (também texto ISO8601), e a data sai do próprio texto.
  defp date_of(%{ts: ts}) when is_binary(ts) do
    case NaiveDateTime.from_iso8601(ts) do
      {:ok, dt} -> NaiveDateTime.to_date(dt)
      _ -> Date.from_iso8601!(binary_part(ts, 0, 10))
    end
  end
end
