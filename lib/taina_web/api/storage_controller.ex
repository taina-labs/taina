defmodule TainaWeb.API.StorageController do
  @moduledoc """
  O armazenamento da comunidade (RFC_005 secao 9): o retrato para todo morador
  e a cota, que so a zeladora muda.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias Taina.Ybira
  alias TainaWeb.API.Error
  alias TainaWeb.API.Serializer

  def show(conn, _params) do
    scope = conn.assigns[:current_scope]

    with {:ok, stats} <- Ybira.storage_stats(scope),
         {:ok, by_kind} <- Ybira.storage_stats_by_kind(scope),
         {:ok, files} <- Ybira.count_files(scope),
         {:ok, photos} <- Ybira.count_photos(scope),
         {:ok, trash} <- Ybira.trash_stats(scope) do
      json(conn, Serializer.storage(stats, by_kind, files, photos, trash))
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def update_quota(conn, params) do
    case quota(params["quota_bytes"]) do
      {:ok, quota_bytes} ->
        case Maraca.update_tekoa_quota(conn.assigns[:current_scope], quota_bytes) do
          {:ok, tekoa} -> json(conn, Serializer.tekoa(tekoa))
          {:error, reason} -> Error.reply(conn, reason)
        end

      :error ->
        Error.reply(conn, :invalid_action)
    end
  end

  defp quota(value) when is_integer(value) and value > 0, do: {:ok, value}

  defp quota(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp quota(_value), do: :error
end
