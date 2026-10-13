defmodule Taina.Ybira.Workers.Rendition do
  @moduledoc """
  Gera as renditions de uma imagem após o upload: thumbnails (2 tamanhos, WebP)
  e metadados leves (dimensões + data de captura do EXIF), gravados nos
  metadados de foto do produto (`Taina.Jaci.Photo` -- o `ybira_files` do kernel
  nao tem coluna de metadata). Enfileirado por `Taina.Ybira.upload/2` quando o
  arquivo é uma imagem (ver RFC 002, Fase 3 / D8).

  As renditions são uma feature da caixa sobre os bytes do kernel; o Jaci só
  **lê** o resultado para montar a galeria, composição, não herança.

  Tudo é *best-effort*: HEIC sem suporte na libvips ou um arquivo corrompido
  não devem virar retentativa infinita nem job morto barulhento. Falhou,
  logamos e devolvemos `:ok`, a foto ainda existe, só não ganha thumbnail.

  Roda em nível de sistema (cruza Tekoas), então recebe o `tekoa_public_id` nos
  args e faz todo o trabalho dentro de `Repo.with_tekoa/2`.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  import Ecto.Query

  alias Taina.Blobs
  alias Taina.Jaci.Photo
  alias Taina.Repo
  alias Taina.Ybira.Media
  alias Ypy.BlobStore.Disk
  alias Ypy.Cid
  alias Ypy.Ybira.File, as: YbiraFile

  require Logger

  # Maior aresta (px) de cada thumbnail: "sm" para a grade da galeria, "md" para
  # a visualização fullscreen. Os caminhos vão para `metadata["thumbnails"]`.
  @sizes %{"sm" => 400, "md" => 1600}

  @doc """
  Gera as renditions de um arquivo de imagem pelo `id`, dentro da Tekoa de
  `tekoa_public_id` (abre o `Repo.with_tekoa/2` por conta própria).

  Ponto de entrada tanto do job (`perform/1`) quanto do mix task
  `taina.thumbnails.regenerate`. Arquivo que não existe nessa Tekoa (apagado,
  expurgado ou de outra comunidade) volta `{:error, :gone}`; falha de
  processamento volta `{:error, reason}`; sucesso volta `:ok`.
  """
  def render_file(file_id, tekoa_public_id) do
    result =
      Repo.with_tekoa(tekoa_public_id, fn ->
        case Repo.one(from(f in YbiraFile, where: f.id == ^file_id and is_nil(f.apagado_em))) do
          # Arquivo deletado (lixeira ou expurgo) entre o upload e o
          # processamento, nada a fazer.
          nil ->
            {:error, :gone}

          file ->
            {:ok, render(file, tekoa_public_id)}
        end
      end)

    case result do
      {:ok, :ok} -> :ok
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, _reason} = error -> error
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"file_id" => file_id, "tekoa_public_id" => tekoa_public_id}}) do
    # Best-effort: falha de rendition não vira retentativa nem job morto
    # barulhento, a foto existe, só não ganha thumbnail.
    _ = render_file(file_id, tekoa_public_id)
    :ok
  end

  defp render(%YbiraFile{} = file, tekoa_public_id) do
    with {:ok, blob_path} <- Disk.open(Blobs.new(), Cid.parse(file.blob_cid)),
         {:ok, info} <- Media.analyze(blob_path),
         {:ok, thumbnails} <- generate_thumbnails(file, tekoa_public_id, blob_path) do
      metadata = %{
        "width" => info.width,
        "height" => info.height,
        "taken_at" => encode_taken_at(info.taken_at),
        "thumbnails" => thumbnails
      }

      save_metadata(file, metadata)
    else
      error ->
        Logger.warning("Rendition: processamento falhou",
          file_id: file.id,
          reason: inspect(error)
        )

        error
    end
  rescue
    e ->
      Logger.warning("Rendition: exceção ao processar", file_id: file.id, reason: inspect(e))
      {:error, e}
  end

  # A rendicao fica na tabela do produto; reprocessar substitui (upsert pelo
  # file_id unico). Best-effort: a foto já existe; logamos a falha e seguimos.
  defp save_metadata(%YbiraFile{} = file, metadata) do
    %Photo{file_id: file.id}
    |> Photo.changeset(%{metadata: metadata})
    |> Repo.insert(
      on_conflict: [set: [metadata: metadata, updated_at: DateTime.truncate(DateTime.utc_now(), :second)]],
      conflict_target: :file_id
    )
    |> case do
      {:ok, _photo} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Rendition: falha ao gravar metadata",
          file_id: file.id,
          errors: inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  defp generate_thumbnails(%YbiraFile{} = file, tekoa_public_id, blob_path) do
    Enum.reduce_while(@sizes, {:ok, %{}}, fn {name, max_edge}, {:ok, acc} ->
      dest = thumbnail_path(tekoa_public_id, file.rkey, name)

      case Media.thumbnail(blob_path, dest, max_edge) do
        :ok -> {:cont, {:ok, Map.put(acc, name, dest)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  # Thumbnails ficam ao lado dos blobs, sob a Tekoa:
  # {storage_root}/{tekoa}/thumbnails/{rkey}_{tamanho}.webp
  defp thumbnail_path(tekoa_public_id, file_rkey, name) do
    Path.join([
      Application.fetch_env!(:taina, :storage_root),
      tekoa_public_id,
      "thumbnails",
      "#{file_rkey}_#{name}.webp"
    ])
  end

  defp encode_taken_at(nil), do: nil
  defp encode_taken_at(%NaiveDateTime{} = dt), do: NaiveDateTime.to_iso8601(dt)
end
