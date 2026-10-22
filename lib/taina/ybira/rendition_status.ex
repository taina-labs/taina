defmodule Taina.Ybira.RenditionStatus do
  @moduledoc """
  Estado da rendição de um arquivo, derivado da linha de foto do produto
  (`Taina.Jaci.Photo`) que o worker de renditions grava. É o contrato
  consumido pelo serializer da API e pela rota de thumbnail (revisão 0.1.0,
  seção A): é o que permite ao cliente distinguir "ainda processando" de
  "nunca vai ter miniatura".

  - `:none`: o arquivo não é imagem (`mime` fora de `image/*`), nada a
    renderizar.
  - `:ready`: linha de foto com `metadata["thumbnails"]` não vazio.
  - `:unavailable`: linha de foto com `metadata["rendition_error"]`: o
    processamento falhou e a falha ficou registrada (revisão 0.1.0, C3).
  - `:pending`: imagem cuja rendição ainda não rodou (sem linha de foto).
  """

  import Ecto.Query

  alias Taina.Jaci.Photo
  alias Taina.Repo
  alias Ypy.Scope
  alias Ypy.Ybira.File

  @typedoc "Estado da rendição, no vocabulário do contrato da API."
  @type status :: :ready | :pending | :unavailable | :none

  @doc """
  Deriva o estado da rendição de `file` dentro da Tekoa do `scope`. Abre o
  `Repo.with_tekoa/2` por conta própria, então pode ser chamado de qualquer
  ponto que já tenha um `Scope` (serializer, controller, LiveView). Uma
  consulta por arquivo: quem lista muitos e se importa com o custo decide
  como agrupar por fora.
  """
  @spec status(Scope.t(), File.t()) :: status()
  def status(%Scope{} = scope, %File{} = file) do
    if image?(file.mime) do
      {:ok, state} =
        Repo.with_tekoa(scope.tekoa.public_id, fn ->
          {:ok, photo_status(file.id)}
        end)

      state
    else
      :none
    end
  end

  defp image?(mime) when is_binary(mime), do: String.starts_with?(mime, "image/")
  defp image?(_mime), do: false

  defp photo_status(file_id) do
    case Repo.one(from(p in Photo, where: p.file_id == ^file_id)) do
      nil -> :pending
      %Photo{metadata: metadata} -> status_from_metadata(metadata || %{})
    end
  end

  # Pura, sobre os metadados que o worker grava. O upsert substitui o mapa
  # inteiro a cada rodada, então `thumbnails` e `rendition_error` não
  # convivem: sucesso grava thumbnails e limpa o erro, falha grava o erro
  # sem thumbnails. A ordem da checagem segue o contrato (pronto antes de
  # falho).
  defp status_from_metadata(metadata) do
    cond do
      thumbnails?(metadata) -> :ready
      has_error?(metadata) -> :unavailable
      true -> :pending
    end
  end

  defp thumbnails?(%{"thumbnails" => thumbnails}) when is_map(thumbnails), do: map_size(thumbnails) > 0

  defp thumbnails?(_metadata), do: false

  defp has_error?(%{"rendition_error" => error}) when is_binary(error), do: error != ""
  defp has_error?(_metadata), do: false
end
