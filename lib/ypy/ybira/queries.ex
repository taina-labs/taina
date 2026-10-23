defmodule Ypy.Ybira.Queries do
  @moduledoc """
  Construtores de query do Ybira, com `tekoa_id` explicito em todo `WHERE`, e
  a regra de leitura das duas zonas no nivel da query (RFC_003 D2): praca OU
  dono OU concessao ativa.
  """

  import Ecto.Query

  alias Ypy.Maraca.Concessao
  alias Ypy.Scope
  alias Ypy.Ybira.File
  alias Ypy.Ybira.Folder

  @doc "Arquivos nao apagados de uma Tekoa, mais recentes primeiro."
  def files(tekoa_id, opts \\ []) do
    query = from(f in File, where: f.tekoa_id == ^tekoa_id)

    query =
      if opts[:lixeira],
        do: where(query, [f], not is_nil(f.apagado_em)),
        else: where(query, [f], is_nil(f.apagado_em))

    query = if folder = opts[:folder], do: where(query, [f], f.folder_id == ^folder), else: query
    query = if zona = opts[:zona], do: where(query, [f], f.zona == ^zona), else: query
    query = if cursor = opts[:cursor], do: where(query, [f], f.rkey < ^cursor), else: query

    from(f in query, order_by: [desc: f.rkey], limit: ^(opts[:limit] || 50))
  end

  @doc "Pastas nao apagadas de uma Tekoa, mais recentes primeiro."
  def folders(tekoa_id, opts \\ []) do
    query = from(p in Folder, where: p.tekoa_id == ^tekoa_id)

    query =
      if opts[:lixeira],
        do: where(query, [p], not is_nil(p.apagado_em)),
        else: where(query, [p], is_nil(p.apagado_em))

    query = if parent = opts[:parent], do: where(query, [p], p.parent_id == ^parent), else: query
    query = if zona = opts[:zona], do: where(query, [p], p.zona == ^zona), else: query
    query = if cursor = opts[:cursor], do: where(query, [p], p.rkey < ^cursor), else: query

    from(p in query, order_by: [desc: p.rkey], limit: ^(opts[:limit] || 50))
  end

  @doc """
  A regra de leitura para arquivos: acrescenta ao `query` (ja escopado por
  Tekoa) a disjuntiva praca OU dono OU concessao ativa de leitura.
  """
  def readable(query, %Scope{} = scope) do
    avail = concessoes(scope, "ypy.file.v0")

    from(f in query,
      where:
        f.zona == :praca or f.dono_id == ^scope.ava.id or
          f.rkey in subquery(avail)
    )
  end

  @doc "A regra de leitura para pastas (a zona e a da pasta)."
  def readable_folder(query, %Scope{} = scope) do
    avail = concessoes(scope, "ypy.folder.v0")

    from(p in query,
      where:
        p.zona == :praca or p.dono_id == ^scope.ava.id or
          p.rkey in subquery(avail)
    )
  end

  @doc "Arquivo ou pasta pelo rkey, dentro da Tekoa; lixeira e opt-in."
  def recurso(schema, tekoa_id, rkey, lixeira? \\ false)

  def recurso(File, tekoa_id, rkey, lixeira?) do
    query =
      from(f in File,
        where: f.tekoa_id == ^tekoa_id,
        where: f.rkey == ^rkey
      )

    if lixeira?, do: query, else: where(query, [f], is_nil(f.apagado_em))
  end

  def recurso(Folder, tekoa_id, rkey, lixeira?) do
    query =
      from(p in Folder,
        where: p.tekoa_id == ^tekoa_id,
        where: p.rkey == ^rkey
      )

    if lixeira?, do: query, else: where(query, [p], is_nil(p.apagado_em))
  end

  defp concessoes(scope, tipo) do
    from(c in Concessao,
      where: c.tekoa_id == ^scope.tekoa.id,
      where: c.leitor_id == ^scope.ava.id,
      where: c.tipo == ^tipo,
      where: is_nil(c.revogada_em),
      select: c.recurso
    )
  end
end
