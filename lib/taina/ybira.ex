defmodule Taina.Ybira do
  @moduledoc """
  Ybira — sistema de arquivos da comunidade.

  Todas as funções públicas recebem um `Taina.Scope` (quem + qual Tekoa) e
  executam dentro de `Repo.with_tekoa/2`, ativando o isolamento RLS.

  Os bytes ficam no disco em
  `{storage_root}/{tekoa_public_id}/files/{ano}/{mes}/{nome}.{ext}`;
  o banco guarda apenas metadados. `storage_root` vem de
  `config :taina, :storage_root`.
  """

  import Ecto.Query

  alias Taina.Maraca.Tekoa
  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira

  @hash_chunk_bytes 1024 * 1024

  @doc """
  Faz upload de um arquivo a partir de um caminho temporário.

  ## Opções

    * `:filename` - nome original do arquivo (default: basename do caminho)
    * `:folder_id` - id interno da pasta de destino (default: raiz)

  Verifica a cota da Tekoa, copia os bytes para o storage definitivo e insere
  o registro — cota e inserção na mesma transação. Em caso de erro, o arquivo
  copiado é removido do disco.
  """
  @spec upload(Scope.t(), Path.t(), keyword) :: {:ok, Ybira.File.t()} | {:error, term}
  def upload(%Scope{} = scope, tmp_path, opts \\ []) do
    original_filename = Keyword.get(opts, :filename, Path.basename(tmp_path))
    folder_id = Keyword.get(opts, :folder_id)

    with {:ok, %{size: size}} <- Elixir.File.stat(tmp_path),
         {:ok, hash} <- hash_file(tmp_path),
         {:ok, dest} <- copy_to_storage(scope, tmp_path, original_filename) do
      attrs = %{
        filename: Path.basename(dest),
        original_filename: original_filename,
        filepath: dest,
        mime_type: MIME.from_path(original_filename),
        file_size_bytes: size,
        file_hash: hash,
        ava_id: scope.ava.id,
        tekoa_id: scope.tekoa.id,
        folder_id: folder_id
      }

      case insert_within_quota(scope, attrs, size) do
        {:ok, file} ->
          {:ok, file}

        {:error, reason} ->
          Elixir.File.rm(dest)
          {:error, reason}
      end
    end
  end

  defp insert_within_quota(%Scope{} = scope, attrs, size) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      with :ok <- quota_check(scope.tekoa.id, size),
           {:ok, file} <- Repo.insert(Ybira.File.changeset(%Ybira.File{}, attrs)) do
        adjust_storage_used(scope.tekoa.id, size)
        {:ok, file}
      end
    end)
  end

  @doc """
  Busca um arquivo pelo `public_id`, dentro da Tekoa do scope.
  """
  @spec get_file(Scope.t(), String.t()) :: {:ok, Ybira.File.t()} | {:error, :not_found}
  def get_file(%Scope{} = scope, file_public_id) when is_binary(file_public_id) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      case Repo.get_by(Ybira.File, public_id: file_public_id) do
        nil -> {:error, :not_found}
        file -> {:ok, file}
      end
    end)
  end

  @doc """
  Lista arquivos não-deletados de uma pasta (`public_id`) ou da raiz (`nil`).
  """
  @spec list_files(Scope.t(), String.t() | nil) :: {:ok, [Ybira.File.t()]}
  def list_files(%Scope{} = scope, folder_public_id \\ nil) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      base =
        from f in Ybira.File,
          where: is_nil(f.deleted_at),
          order_by: [desc: f.inserted_at, desc: f.id]

      query =
        case folder_public_id do
          nil ->
            from f in base, where: is_nil(f.folder_id)

          public_id when is_binary(public_id) ->
            from f in base,
              join: d in Ybira.Folder,
              on: d.id == f.folder_id,
              where: d.public_id == ^public_id
        end

      {:ok, Repo.all(query)}
    end)
  end

  @doc """
  Remove um arquivo do banco e do disco. Apenas o dono pode remover
  (verificações de admin chegam com `Maraca.authorize?/4`).
  """
  @spec delete_file(Scope.t(), String.t()) :: {:ok, Ybira.File.t()} | {:error, :not_found | term}
  def delete_file(%Scope{} = scope, file_public_id) when is_binary(file_public_id) do
    result =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        query =
          from f in Ybira.File,
            where: f.public_id == ^file_public_id,
            where: f.ava_id == ^scope.ava.id

        with %Ybira.File{} = file <- Repo.one(query) || {:error, :not_found},
             {:ok, file} <- Repo.delete(file) do
          adjust_storage_used(scope.tekoa.id, -file.file_size_bytes)
          {:ok, file}
        end
      end)

    with {:ok, file} <- result do
      Elixir.File.rm(file.filepath)
      {:ok, file}
    end
  end

  @doc """
  Verifica se a Tekoa do scope comporta mais `byte_size` bytes.
  """
  @spec check_capacity(Scope.t(), pos_integer) :: :ok | {:error, :storage_quota_exceeded}
  def check_capacity(%Scope{} = scope, byte_size) do
    {:ok, result} =
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok, quota_check(scope.tekoa.id, byte_size)}
      end)

    result
  end

  defp quota_check(tekoa_id, byte_size) do
    tekoa = Repo.get!(Tekoa, tekoa_id)

    cond do
      is_nil(tekoa.storage_quota_bytes) -> :ok
      tekoa.storage_used_bytes + byte_size <= tekoa.storage_quota_bytes -> :ok
      true -> {:error, :storage_quota_exceeded}
    end
  end

  defp adjust_storage_used(tekoa_id, delta) do
    Repo.update_all(from(t in Tekoa, where: t.id == ^tekoa_id), inc: [storage_used_bytes: delta])
  end

  defp copy_to_storage(%Scope{} = scope, tmp_path, original_filename) do
    today = Date.utc_today()

    dir =
      Path.join([
        storage_root(),
        scope.tekoa.public_id,
        "files",
        Integer.to_string(today.year),
        String.pad_leading(Integer.to_string(today.month), 2, "0")
      ])

    dest = Path.join(dir, Nanoid.generate(12) <> Path.extname(original_filename))

    with :ok <- Elixir.File.mkdir_p(dir),
         :ok <- Elixir.File.cp(tmp_path, dest) do
      {:ok, dest}
    end
  end

  defp hash_file(path) do
    hash =
      path
      |> Elixir.File.stream!(@hash_chunk_bytes)
      |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
      |> :crypto.hash_final()
      |> Base.encode16(case: :lower)

    {:ok, hash}
  rescue
    e in Elixir.File.Error -> {:error, e.reason}
  end

  defp storage_root, do: Application.fetch_env!(:taina, :storage_root)
end
