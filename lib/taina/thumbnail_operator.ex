defmodule Taina.ThumbnailOperator do
  @moduledoc "Release-safe thumbnail regeneration operation."
  import Ecto.Query

  alias Taina.Repo
  alias Taina.Ybira.Workers.Rendition
  alias Ypy.Maraca.Tekoa
  alias Ypy.Ybira.File

  def regenerate(tekoa_id \\ nil) do
    with {:ok, tekoas} <- list_tekoas(tekoa_id) do
      {:ok, Enum.map(tekoas, &regenerate_tekoa/1)}
    end
  end

  defp list_tekoas(nil), do: Repo.with_system(fn -> {:ok, Repo.all(Tekoa, skip_tekoa_id: true)} end)

  defp list_tekoas(public_id),
    do: Repo.with_system(fn -> {:ok, [Repo.get_by!(Tekoa, [public_id: public_id], skip_tekoa_id: true)]} end)

  defp regenerate_tekoa(tekoa) do
    {:ok, files} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok,
         Repo.all(
           from f in File,
             where: f.tekoa_id == ^tekoa.id and is_nil(f.apagado_em) and like(f.mime, "image/%"),
             order_by: [asc: f.id]
         )}
      end)

    counts =
      files
      |> Enum.map(fn file ->
        case Rendition.render_file(file.id, tekoa.public_id) do
          :ok -> :rendered
          {:error, :gone} -> :gone
          _ -> :failed
        end
      end)
      |> Enum.frequencies()

    {tekoa, counts}
  end
end
