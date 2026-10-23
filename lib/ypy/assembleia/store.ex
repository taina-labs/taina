defmodule Ypy.Assembleia.Store do
  @moduledoc """
  A execucao das queries e changesets da assembleia: `repo` sempre primeiro,
  `tekoa_id` explicito em todo filtro. A reclamacao de execucao e um UPDATE
  condicional, unico e atomico, porque uma aprovada so vira um ato.
  """

  import Ecto.Query, only: [where: 3]

  alias Ypy.Assembleia.Proposta
  alias Ypy.Assembleia.Queries

  @doc "A proposta pelo public_id, dentro da Tekoa."
  def get_proposta(repo, tekoa_id, public_id) do
    repo.one(where(Proposta, [p], p.tekoa_id == ^tekoa_id and p.public_id == ^public_id))
  end

  @doc "A proposta pelo id, dentro da Tekoa."
  def get_proposta_por_id(repo, tekoa_id, proposta_id) do
    repo.one(where(Proposta, [p], p.tekoa_id == ^tekoa_id and p.id == ^proposta_id))
  end

  @doc "As propostas de uma Tekoa."
  def propostas(repo, tekoa_id, opts \\ []), do: repo.all(Queries.propostas(tekoa_id, opts))

  @doc "Os votos de uma proposta."
  def votos(repo, tekoa_id, proposta_id), do: repo.all(Queries.votos(tekoa_id, proposta_id))

  @doc "As escolhas de uma proposta, no plano que a politica fala."
  def escolhas(repo, tekoa_id, proposta_id) do
    repo
    |> votos(tekoa_id, proposta_id)
    |> Enum.map(& &1.escolha)
  end

  @doc "Insere pelo changeset dado."
  def insert(repo, changeset), do: repo.insert(changeset)

  @doc "Atualiza pelo changeset dado."
  def update(repo, changeset), do: repo.update(changeset)

  @doc """
  Reclama a executacao uma unica vez: UPDATE condicional em
  `executado_em IS NULL`. Devolve {:ok, proposta} quando reclamou e
  {:error, :already_executed} quando a reclamacao ja foi feita.
  """
  def claim_execucao(repo, tekoa_id, proposta_id, agora) do
    {count, _} =
      Proposta
      |> where(
        [p],
        p.tekoa_id == ^tekoa_id and p.id == ^proposta_id and p.status == :aprovada and
          is_nil(p.executado_em)
      )
      |> repo.update_all(set: [executado_em: agora])

    case count do
      1 -> {:ok, agora}
      _ -> {:error, :already_executed}
    end
  end
end
