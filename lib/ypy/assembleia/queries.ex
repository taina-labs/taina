defmodule Ypy.Assembleia.Queries do
  @moduledoc "Construtores de query da assembleia, com `tekoa_id` explicito."

  import Ecto.Query

  alias Ypy.Assembleia.Proposta
  alias Ypy.Assembleia.Voto

  @doc "As propostas de uma Tekoa, mais recentes primeiro."
  def propostas(tekoa_id, opts \\ []) do
    query = from(p in Proposta, where: p.tekoa_id == ^tekoa_id)
    query = if status = opts[:status], do: where(query, [p], p.status == ^status), else: query
    query = if tipo = opts[:tipo], do: where(query, [p], p.tipo == ^tipo), else: query

    from(p in query, order_by: [desc: p.inserted_at], limit: ^(opts[:limit] || 50))
  end

  @doc "Os votos de uma proposta."
  def votos(tekoa_id, proposta_id) do
    from(v in Voto,
      where: v.tekoa_id == ^tekoa_id,
      where: v.proposta_id == ^proposta_id,
      order_by: [asc: v.inserted_at]
    )
  end
end
