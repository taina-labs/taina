defmodule TainaWeb.Time do
  @moduledoc """
  Datas e horas no horário da comunidade.

  O banco grava tudo em UTC, mas quem lê o mural, a linha do tempo e a Saúde
  vive num fuso: um ato das 23h de UTC pode ter acontecido "hoje" para a
  comunidade. O deslocamento vem da configuração da caixa
  (`config :taina, :community_utc_offset`, em horas) e o default é -3, o fuso
  de Brasília, o caso do MVP. Ajuste de configuração, não decisão de tela.

  Só datas e horas simples: nada de zona nomeada (a caixa não carrega tzdata
  e não ganha essa dependência por causa de um rótulo de dia).
  """

  @default_utc_offset_hours -3

  @doc """
  Data local da comunidade para um instante. Aceita `DateTime` e
  `NaiveDateTime` (o formato dos `timestamps` do Ecto, gravado em UTC).
  """
  def local_date(%DateTime{} = at), do: at |> shifted_local() |> DateTime.to_date()

  def local_date(%NaiveDateTime{} = at) do
    at |> DateTime.from_naive!("Etc/UTC") |> local_date()
  end

  @doc "Hoje, na data local da comunidade."
  def local_today, do: local_date(DateTime.utc_now())

  @doc "Hora local no formato do relógio, HH:MM."
  def local_clock(%DateTime{} = at), do: at |> shifted_local() |> Calendar.strftime("%H:%M")

  def local_clock(%NaiveDateTime{} = at) do
    at |> DateTime.from_naive!("Etc/UTC") |> local_clock()
  end

  defp shifted_local(at), do: DateTime.shift(at, second: offset_seconds())

  defp offset_seconds, do: local_offset_hours() * 3600

  defp local_offset_hours do
    Application.get_env(:taina, :community_utc_offset, @default_utc_offset_hours)
  end
end
