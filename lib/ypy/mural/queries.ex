defmodule Ypy.Mural.Queries do
  @moduledoc "Construtores de query da cadeia, com `tekoa_id` explicito."

  import Ecto.Query

  alias Ypy.Mural.Entry

  @doc "A cabeca da cadeia: a entrada de maior seq."
  def head(tekoa_id) do
    from(e in Entry,
      where: e.tekoa_id == ^tekoa_id,
      order_by: [desc: e.seq],
      limit: 1
    )
  end

  @doc "A cadeia inteira, do genesis em diante."
  def entradas(tekoa_id) do
    from(e in Entry, where: e.tekoa_id == ^tekoa_id, order_by: [asc: e.seq])
  end

  @doc "Uma entrada pelo seq."
  def por_seq(tekoa_id, seq) do
    from(e in Entry, where: e.tekoa_id == ^tekoa_id, where: e.seq == ^seq)
  end

  @doc "As entradas de um tipo (a projecao do mural)."
  def por_tipo(tekoa_id, tipo) do
    from(e in entradas(tekoa_id), where: e.tipo == ^tipo)
  end

  @doc "Paginacao por cursor de seq: ate (exclusive) o seq dado."
  def antes(query, seq), do: from(e in query, where: e.seq < ^seq)
end
