defmodule Mix.Tasks.Taina.Thumbnails.Regenerate do
  @shortdoc "Regera as miniaturas (thumbnails) das imagens ativas do Ybira"

  @moduledoc """
  Regera as renditions de todas as imagens ativas (ou de uma Tekoa só, com
  `--tekoa <public_id>`), do mesmo jeito que o worker `Rendition` faz depois
  de cada upload: dois tamanhos em WebP mais metadados (dimensões, data de
  captura). Idempotente: quem já tem thumbnail regenera por cima.

  Use quando o diretório de thumbnails se perdeu no disco ou depois de uma
  mudança no formato das miniaturas. Cada arquivo conta como gerado, ausente
  (`:gone`, apagado/expurgado) ou falhado (disco, corrompido), e o resumo sai
  no fim; nenhuma falha para o resto.

  Não sobe a app inteira (endpoint e fila não são precisos aqui): só o Repo.

      mix taina.thumbnails.regenerate
      mix taina.thumbnails.regenerate --tekoa <public_id>
  """

  use Mix.Task

  import Ecto.Query

  alias Taina.Maraca.Tekoa
  alias Taina.Repo
  alias Taina.Ybira.File
  alias Taina.Ybira.Workers.Rendition

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _invalid} = OptionParser.parse!(args, strict: [tekoa: :string])

    # A app inteira não sobe aqui (endpoint e fila não são precisos), só o
    # Repo, que já está de pé quando a tarefa roda por cima de uma app viva.
    if is_nil(Process.whereis(Repo)) do
      {:ok, _} = Repo.start_link()
    end

    results =
      opts[:tekoa]
      |> list_tekoas()
      |> Enum.map(&regenerate_tekoa/1)

    print_summary(results)
  end

  # `skip_tekoa_id: true`: listar as comunidades é operação de sistema, feita
  # antes de haver contexto RLS de alguma delas. A válvula (`with_system/1`)
  # espelha isso no banco: sem ela, o papel de aplicação (RLS ativo em
  # produção) veria zero Tekoas e a tarefa não faria nada.
  defp list_tekoas(nil) do
    {:ok, tekoas} = Repo.with_system(fn -> {:ok, Repo.all(Tekoa, skip_tekoa_id: true)} end)

    tekoas
  end

  defp list_tekoas(public_id) do
    {:ok, tekoa} =
      Repo.with_system(fn ->
        {:ok, Repo.get_by!(Tekoa, [public_id: public_id], skip_tekoa_id: true)}
      end)

    [tekoa]
  end

  # Imagens ativas da Tekoa (fora da lixeira), renditions geradas em linha,
  # uma a uma, dentro do contexto RLS de cada comunidade.
  defp regenerate_tekoa(tekoa) do
    {:ok, files} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok,
         Repo.all(
           from(f in File,
             where: is_nil(f.deleted_at) and like(f.mime_type, "image/%"),
             order_by: [asc: f.id]
           )
         )}
      end)

    counts =
      Enum.map(files, fn file ->
        case Rendition.render_file(file.id, tekoa.public_id) do
          :ok -> :rendered
          {:error, :gone} -> :gone
          {:error, _reason} -> :failed
        end
      end)

    {tekoa, Enum.frequencies(counts)}
  end

  defp print_summary(results) do
    Enum.each(results, fn {tekoa, counts} ->
      Mix.shell().info([
        "  #{tekoa.name} (#{tekoa.public_id}): ",
        "#{Map.get(counts, :rendered, 0)} geradas, ",
        "#{Map.get(counts, :gone, 0)} ausentes, ",
        "#{Map.get(counts, :failed, 0)} falharam"
      ])
    end)

    total = results |> Enum.map(fn {_tekoa, counts} -> Map.get(counts, :rendered, 0) end) |> Enum.sum()

    Mix.shell().info([:green, "miniaturas regeradas: #{total}", :reset])
  end
end
