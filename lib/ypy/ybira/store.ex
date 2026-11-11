defmodule Ypy.Ybira.Store do
  @moduledoc """
  A execucao das queries e changesets do Ybira: `repo` sempre primeiro,
  `tekoa_id` explicito em todo filtro. Nenhuma regra aqui.
  """

  import Ecto.Query, only: [from: 2, where: 3]

  alias Ypy.Ybira.Blob
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder
  alias Ypy.Ybira.Queries

  @doc "O rkey da pasta pelo id (para o payload do envelope do arquivo)."
  def folder_rkey(_repo, nil), do: nil

  def folder_rkey(repo, folder_id) do
    repo.one(from(p in Folder, where: p.id == ^folder_id, select: p.rkey))
  end

  @doc "A linha do blob, para saber se os bytes ja sao da Tekoa."
  def get_blob(repo, tekoa_id, cid) do
    repo.one(where(Blob, [b], b.tekoa_id == ^tekoa_id and b.cid == ^cid))
  end

  @doc "O arquivo pelo rkey; lixeira so com opt-in."
  def get_file(repo, tekoa_id, rkey, lixeira? \\ false) do
    get_recurso(repo, File, tekoa_id, rkey, lixeira?)
  end

  @doc "A pasta pelo rkey; lixeira so com opt-in."
  def get_folder(repo, tekoa_id, rkey, lixeira? \\ false) do
    get_recurso(repo, Folder, tekoa_id, rkey, lixeira?)
  end

  @doc "O recurso pelo rkey (arquivo ou pasta, dado o schema); lixeira so com opt-in."
  def get_recurso(repo, schema, tekoa_id, rkey, lixeira? \\ false) do
    repo.one(Queries.recurso(schema, tekoa_id, rkey, lixeira?))
  end

  @doc "Registra a existencia do blob (dedup por conteudo)."
  def put_blob(repo, changeset) do
    repo.insert(changeset, on_conflict: :nothing, conflict_target: [:tekoa_id, :cid])
  end
end
