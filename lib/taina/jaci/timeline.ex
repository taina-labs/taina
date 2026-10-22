defmodule Taina.Jaci.Timeline do
  @moduledoc """
  Núcleo puro da linha do tempo do Jaci. Sem banco, sem efeito colateral: só
  agrupa uma lista já ordenada em baldes por dia.

  A data efetiva de uma foto é a captura do EXIF (`metadata["taken_at"]` das
  rendições do produto) quando existe; senão, o instante do upload
  (`inserted_at`), o "mtime" da RFC 002, Fase 3. A resolução acontece na
  consulta (`Taina.Jaci`), que normaliza as duas fontes para o mesmo inteiro
  canônico: epoch de segundos (UTC). O SQLite lê texto sem zona como UTC,
  que é o máximo que um EXIF sem timezone permite; o instante do upload já é
  UTC. Daqui em diante a data já vem na linha, decodificada do epoch.
  """

  alias Ypy.Ybira.File

  @typedoc "Um dia da linha do tempo: a data e as fotos daquele dia, mais novas primeiro."
  @type group :: %{date: Date.t(), photos: [File.t()]}

  @doc """
  Agrupa linhas **já ordenadas por data efetiva decrescente** (`%{file:,
  ts:}`, o epoch de segundos resolvido na consulta) em baldes diários
  consecutivos. Como a entrada vem ordenada, todas as fotos de um mesmo dia
  são contíguas, `chunk_by` basta. Em paginação, um dia pode se repartir
  entre o fim de uma página e o início da próxima; a UI funde grupos de
  mesma data adjacentes.
  """
  @spec group_by_date([%{file: File.t(), ts: integer()}]) :: [group()]
  def group_by_date(rows) do
    rows
    |> Enum.chunk_by(&date_of/1)
    |> Enum.map(fn [first | _] = chunk ->
      %{date: date_of(first), photos: Enum.map(chunk, & &1.file)}
    end)
  end

  # O epoch chega em segundos (UTC); o dia sai dele, sem fuso local: o mesmo
  # instante tem o mesmo dia nas duas fontes da consulta.
  defp date_of(%{ts: epoch}) when is_integer(epoch) do
    epoch
    |> DateTime.from_unix!()
    |> DateTime.to_date()
  end
end
