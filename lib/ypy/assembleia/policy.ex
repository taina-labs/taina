defmodule Ypy.Assembleia.Policy do
  @moduledoc """
  A matematica da assembleia (RFC_003 secao 8): quorum, maioria simples e o
  prazo de uma proposta.

  Os verbos, o armazenamento e o worker que fecha propostas sao do produto;
  aqui ficam as respostas que o ciclo precisa. Votos chegam como a lista de
  escolhas, `:sim` e `:nao`, e a unicidade de voto por morador e do banco, nao
  daqui. Ato sensivel nenhum roda sem proposta aprovada como token de
  autoridade; a politica so diz o que a comunidade decidiu.
  """

  @typedoc "A escolha de um voto."
  @type escolha :: :sim | :nao

  @doc "Quorum para uma Tekoa com `moradores` membros: ceil(moradores/2)."
  @spec quorum(non_neg_integer()) :: non_neg_integer()
  def quorum(moradores) when is_integer(moradores) and moradores >= 0, do: ceil(moradores / 2)

  @doc """
  O que uma proposta fechada vale.

  :aprovada quando os votos formam o quorum e a maioria simples diz sim;
  :expirada quando o quorum nao se forma, mesmo com todos os poucos votos dizendo
  sim; :rejeitada quando o quorum se forma e nao aprova, empate incluso. Uma
  escolha que nao e :sim nem :nao nao e um voto e nao conta.
  """
  @spec tally([escolha], non_neg_integer()) :: :aprovada | :rejeitada | :expirada
  def tally(votes, moradores) when is_list(votes) do
    votes = Enum.filter(votes, &(&1 in [:sim, :nao]))

    if length(votes) < quorum(moradores) do
      :expirada
    else
      if Enum.count(votes, &(&1 == :sim)) > Enum.count(votes, &(&1 == :nao)),
        do: :aprovada,
        else: :rejeitada
    end
  end

  @doc """
  O prazo de uma proposta aberta passou? Passar do prazo expira; no proprio
  prazo ainda vale, e so a virada expira.
  """
  @spec expired?(DateTime.t(), DateTime.t()) :: boolean()
  def expired?(%DateTime{} = closes_at, %DateTime{} = now), do: DateTime.after?(now, closes_at)
end
