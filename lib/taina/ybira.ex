defmodule Taina.Ybira do
  @moduledoc false

  import Ecto.Query

  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa
  alias Taina.Repo
  alias Taina.Ybira

  @root_path "/var/taina/storage/communities"

  @spec get_file(binary) :: {:ok, Ybira.File.t()} | {:error, :not_found}
  def get_file(file_id) when is_binary(file_id) do
    if file = Repo.get_by(File, public_id: file_id) do
      {:ok, file}
    else
      {:error, :not_found}
    end
  end

  @spec delete_file(String.t(), String.t()) :: {:ok, nil} | {:error, any}
  def delete_file(file_id, user_id) when is_binary(file_id) and is_binary(user_id) do
    query = from f in Ybira.File, where: f.public_id == ^file_id, where: f.ava_id == ^user_id

    Repo.transact(fn ->
      file = Repo.one!(query)
      Repo.delete!(file)
      File.rm!(file.filepath)
      {:ok, nil}
    end)
  end

  @spec list_files(String.t()) :: {:ok, list(Ybira.File.t())} | {:error, any}
  def list_files(folder_id) when is_binary(folder_id) do
    query = from f in Ybira.File, where: f.folder_id == ^folder_id

    case Repo.all(query) do
      [] -> {:error, :not_found}
      files -> {:ok, files}
    end
  end

  @spec upload(String.t(), Path.t()) :: {:ok, Ybira.File.t()} | {:error, any}
  def upload(user_id, tmp_file_path) do
    mime_type = MIME.from_path(tmp_file_path)

    with {:ok, stat} <- File.stat(tmp_file_path),
         :ok <- check_capacity(user_id, stat.size) do
    end
  end

  @spec check_capacity(String.t(), integer) :: :ok | {:error, any}
  def check_capacity(user_id, byte_size) do
    query = from a in Ava, where: a.id == ^user_id, join: t in Tekoa, on: t.id == a.tekoa_id, select: t
    tekoa = Repo.one(query)

    cond do
      is_nil(tekoa) -> {:error, :not_found}
      tekoa.used_storage + byte_size <= tekoa.storage_quota -> :ok
      true -> {:error, :storage_quota_exceeded}
    end
  end
end
