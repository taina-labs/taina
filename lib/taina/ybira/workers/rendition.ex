defmodule Taina.Ybira.Workers.Rendition do
  @moduledoc """
  Gera as renditions de uma imagem após o upload: thumbnails (2 tamanhos, WebP)
  e metadados leves (dimensões + data de captura do EXIF), gravados nos
  metadados de foto do produto (`Taina.Jaci.Photo` -- o `ybira_files` do kernel
  nao tem coluna de metadata). Enfileirado por `Taina.Ybira.upload/2` quando o
  arquivo é uma imagem (ver RFC 002, Fase 3 / D8).

  A data de captura também entra como dica de ordem no kernel: o
  `effective_at` de `ybira_files` (kernel 0.2) recebe o EXIF ANTES da geração
  de thumbnails, então a linha do tempo do Jaci ordena pela captura mesmo
  quando a miniatura falha em seguida. Sem EXIF, `effective_at` fica nulo e
  o fallback é o instante do upload.

  As renditions são uma feature da caixa sobre os bytes do kernel; o Jaci só
  **lê** o resultado para montar a galeria, composição, não herança.

  Tudo é *best-effort*: HEIC sem decodificador na libvips ou um arquivo
  corrompido não devem virar retentativa infinita nem job morto barulhento.
  Falhou, registramos o motivo nos metadados da foto (`rendition_error`) e
  devolvemos `{:error, _}` sem retentar: a foto existe, só não ganha
  thumbnail, e o cliente distingue "pendente" de "indisponível" (revisão
  0.1.0, C3). Uma rodada posterior bem-sucedida substitui os metadados e
  limpa o erro.

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
         # A dica de ordem do kernel entra ANTES das thumbnails: mesmo quando
         # a geração de miniatura falha em seguida, a linha do tempo já
         # ordena pela data de captura.
         :ok <- set_effective_at(file, info.taken_at),
         {:ok, thumbnails} <- generate_thumbnails(file, tekoa_public_id, blob_path) do
      metadata = %{
        "width" => info.width,
        "height" => info.height,
        "taken_at" => encode_taken_at(info.taken_at),
        "thumbnails" => thumbnails
      }

      save_metadata(file, metadata)
    else
      {:error, reason} = error ->
        Logger.warning(failure_message(reason), file_id: file.id, reason: inspect(error))

        record_failure(file, reason)

        error
    end
  rescue
    e ->
      Logger.warning("Rendition: exceção ao processar", file_id: file.id, reason: inspect(e))
      record_failure(file, e)
      {:error, e}
  end

  @doc false
  # Publica para o teste (o mesmo padrão de `Media.extract_taken_at/1`: uma
  # imagem com EXIF real não é reproduzível em fixture, a libvips re-encoda
  # o EXIF e o perde). Grava a dica de ordem do kernel (`effective_at`) com a
  # data de captura, que o EXIF traz sem fuso (o cast do Ecto a trata como
  # UTC, a mesma convenção do SQLite na linha do tempo). Best-effort: sem
  # EXIF não há update, e falha de gravação fica no log sem derrubar o job.
  def set_effective_at(_file, nil), do: :ok

  def set_effective_at(%YbiraFile{} = file, %NaiveDateTime{} = taken_at) do
    file
    |> YbiraFile.changeset(%{effective_at: taken_at})
    |> Repo.update()
    |> case do
      {:ok, _file} ->
        :ok

      {:error, changeset} ->
        Logger.warning("Rendition: falha ao gravar a data de captura (effective_at)",
          file_id: file.id,
          errors: inspect(changeset.errors)
        )

        :ok
    end
  end

  # O log nomeia a causa: "a libvips desta caixa não abre esse formato" (ex.:
  # HEIC sem libheif) é problema de ambiente, se resolve na caixa; outros
  # erros (disco, arquivo corrompido) pertencem ao arquivo. Revisão 0.1.0, C3.
  defp failure_message(reason) do
    if Media.unsupported_format?(reason) do
      "Rendition: a libvips desta caixa não tem decodificador para o formato " <>
        "da imagem (ex.: HEIC sem libheif); miniatura não será gerada aqui"
    else
      "Rendition: processamento falhou"
    end
  end

  # A falha fica registrada na foto (`metadata["rendition_error"]`, sem
  # thumbnails), não só no log: é o que separa "pendente" de "indisponível"
  # na API (C3). Upsert como na gravação de sucesso: substitui o mapa
  # inteiro. Best-effort de novo: falhar ao registrar a falha vira log e
  # segue.
  defp record_failure(%YbiraFile{} = file, reason) do
    case save_metadata(file, %{"rendition_error" => inspect(reason)}) do
      :ok ->
        :ok

      {:error, changeset} ->
        Logger.warning("Rendition: falha ao registrar o erro da rendição",
          file_id: file.id,
          errors: inspect(changeset.errors)
        )
    end
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
