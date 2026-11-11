defmodule Taina.ThumbnailOperator do
  @moduledoc "Release-safe thumbnail regeneration operation."
  import Ecto.Query

  alias Taina.Repo
  alias Taina.Ybira.Workers.Rendition
  alias Ypy.Maraca.Tekoa
  alias Ypy.PublicId
  alias Ypy.Ybira.File

  def regenerate(tekoa_id \\ nil) do
    with {:ok, tekoas} <- list_tekoas(tekoa_id), do: regenerate_all(tekoas)
  end

  defp files_in_tekoa(tekoa) do
    Repo.with_tekoa(tekoa.public_id, fn ->
      files =
        Repo.all(
          from f in File,
            where: f.tekoa_id == ^tekoa.id and is_nil(f.apagado_em) and like(f.mime, "image/%"),
            order_by: [asc: f.id]
        )

      {:ok, files}
    end)
  end

  defp find_tekoa(public_id) do
    Repo.with_system(fn ->
      case Repo.get_by(Tekoa, [public_id: public_id], skip_tekoa_id: true) do
        %Tekoa{} = tekoa -> {:ok, [tekoa]}
        nil -> {:error, :not_found}
      end
    end)
  end

  defp list_tekoas(nil), do: Repo.with_system(fn -> {:ok, Repo.all(Tekoa, skip_tekoa_id: true)} end)

  defp list_tekoas(public_id) do
    if PublicId.valid?(public_id), do: find_tekoa(public_id), else: {:error, :not_found}
  end

  defp regenerate_all(tekoas) do
    case Enum.reduce_while(tekoas, {:ok, []}, &regenerate_next/2) do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, _reason} = error -> error
    end
  end

  defp regenerate_next(tekoa, {:ok, results}) do
    case regenerate_tekoa(tekoa) do
      {:ok, result} -> {:cont, {:ok, [result | results]}}
      {:error, _reason} = error -> {:halt, error}
    end
  end

  defp regenerate_tekoa(tekoa) do
    with {:ok, files} <- files_in_tekoa(tekoa) do
      {:ok, {tekoa, rendition_counts(files, tekoa.public_id)}}
    end
  end

  defp render_status(file, tekoa_public_id) do
    case Rendition.render_file(file.id, tekoa_public_id) do
      :ok -> :rendered
      {:error, :gone} -> :gone
      {:error, _reason} -> :failed
    end
  end

  defp rendition_counts(files, tekoa_public_id) do
    files
    |> Enum.map(&render_status(&1, tekoa_public_id))
    |> Enum.frequencies()
  end
end
