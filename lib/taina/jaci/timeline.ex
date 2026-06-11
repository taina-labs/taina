defmodule Taina.Jaci.Timeline do
  @moduledoc """
  Núcleo puro da linha do tempo do Jaci. Sem banco, sem efeito colateral: só
  decide a data de uma foto e agrupa uma lista já ordenada em baldes por dia.

  A data efetiva de uma foto é a captura do EXIF (`metadata["taken_at"]`) quando
  existe; senão, o instante do upload (`inserted_at`) — o "mtime" da RFC 002,
  Fase 3. O EXIF não carrega timezone, então trabalhamos em `NaiveDateTime`.
  """

  alias Taina.Ybira.File, as: YbiraFile

  @typedoc "Um dia da linha do tempo: a data e as fotos daquele dia, mais novas primeiro."
  @type group :: %{date: Date.t(), photos: [YbiraFile.t()]}

  @doc """
  Data/hora efetiva de uma foto: `taken_at` do EXIF quando presente e válido,
  senão o `inserted_at` do upload.
  """
  @spec effective_datetime(YbiraFile.t()) :: NaiveDateTime.t()
  def effective_datetime(%YbiraFile{metadata: metadata, inserted_at: inserted_at}) do
    with taken when is_binary(taken) <- metadata["taken_at"],
         {:ok, dt} <- NaiveDateTime.from_iso8601(taken) do
      dt
    else
      _ -> inserted_at
    end
  end

  @doc """
  Agrupa fotos **já ordenadas por data efetiva decrescente** em baldes diários
  consecutivos. Como a entrada vem ordenada, todas as fotos de um mesmo dia são
  contíguas — `chunk_by` basta. Em paginação, um dia pode se repartir entre o
  fim de uma página e o início da próxima; a UI funde grupos de mesma data
  adjacentes.
  """
  @spec group_by_date([YbiraFile.t()]) :: [group()]
  def group_by_date(photos) do
    photos
    |> Enum.chunk_by(&date_of/1)
    |> Enum.map(fn [first | _] = chunk -> %{date: date_of(first), photos: chunk} end)
  end

  defp date_of(photo), do: photo |> effective_datetime() |> NaiveDateTime.to_date()
end
