defmodule TainaWeb.API.SaudeController do
  @moduledoc """
  A saude da comunidade (RFC_005 secao 9): armazenamento, jobs em espera e o
  ultimo backup, na leitura; o disparo do backup e so da zeladora.
  """

  use TainaWeb, :controller

  alias Taina.Nhaman.Backup
  alias Taina.Nhaman.Workers
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
      storage = Serializer.storage(stats, by_kind, files, photos, trash)
      json(conn, Serializer.saude(storage, Ybira.pending_job_counts(), Backup.last_backup()))
    else
      {:error, reason} -> Error.reply(conn, reason)
    end
  end

  def backup(conn, _params) do
    case Oban.insert(Workers.Backup.new(%{})) do
      {:ok, _job} -> conn |> put_status(202) |> json(%{"scheduled" => true})
      {:error, reason} -> Error.reply(conn, reason)
    end
  end
end
