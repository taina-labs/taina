defmodule Ypy.Assembleia do
  @moduledoc """
  O ciclo da assembleia (RFC_003 secao 8): abrir proposta, votar, apurar e
  fechar, e a reclamacao unica de execucao do ato aprovado.

  A matematica (quorum, maioria, prazo) e do `Ypy.Assembleia.Policy`, puro; a
  unicidade de voto por morador e do banco. Nenhum ato sensivel roda sem
  proposta aprovada como token de autoridade: `executar/3` reclama a
  execucao uma vez e nunca mais ({:error, :already_executed}).
  """

  alias Ypy.Assembleia.Policy
  alias Ypy.Assembleia.Proposta
  alias Ypy.Assembleia.Store
  alias Ypy.Assembleia.Voto
  alias Ypy.Maraca.Store, as: MaracaStore
  alias Ypy.Scope

  @tipos [:remover_morador, :nomear_zelador, :destituir_zelador, :mudar_cota]

  @doc """
  Abre a proposta. O prazo (`:fecha_em`) e decisao de quem abre; o payload
  carrega o alvo do ato em identificadores publicos.
  """
  @spec abrir(
          Ecto.Repo.t(),
          Scope.t(),
          :remover_morador | :nomear_zelador | :destituir_zelador | :mudar_cota,
          map(),
          keyword()
        ) ::
          {:ok, Proposta.t()} | {:error, term()}
  def abrir(repo, %Scope{} = scope, tipo, payload, opts \\ []) when tipo in @tipos do
    with {:ok, fecha_em} <- fetch_fecha_em(opts) do
      Store.insert(
        repo,
        Proposta.changeset(%Proposta{}, %{
          tekoa_id: scope.tekoa.id,
          autor_id: scope.ava.id,
          tipo: tipo,
          payload: payload,
          status: :aberta,
          fecha_em: fecha_em
        })
      )
    end
  end

  @doc """
  O voto do morador na proposta aberta: um por pessoa, :sim ou :nao, ate o
  prazo. Proposta fora do prazo responde {:error, :expirada} e cabe ao
  produto fechar (o worker e dele).
  """
  @spec votar(Ecto.Repo.t(), Scope.t(), Proposta.t(), :sim | :nao) ::
          {:ok, Voto.t()} | {:error, term()}
  def votar(repo, %Scope{} = scope, %Proposta{} = proposta, escolha) when escolha in [:sim, :nao] do
    with :ok <- mesma_tekoa(scope, proposta),
         :ok <- aberta_guard(proposta),
         :ok <- prazo_guard(proposta) do
      Store.insert(
        repo,
        Voto.changeset(%Voto{}, %{
          tekoa_id: scope.tekoa.id,
          proposta_id: proposta.id,
          ava_id: scope.ava.id,
          escolha: escolha
        })
      )
    end
  end

  @doc """
  Fecha a proposta aberta: apura pela politica (quorum ceil(moradores/2),
  maioria simples) e registra :aprovada, :rejeitada ou :expirada. Fechar de
  novo responde {:error, :invalid_status}.
  """
  @spec fechar(Ecto.Repo.t(), integer(), Proposta.t()) ::
          {:ok, Proposta.t()} | {:error, term()}
  def fechar(repo, tekoa_id, %Proposta{id: id}) do
    with {:ok, proposta} <- proposta_atual(repo, tekoa_id, id),
         :ok <- aberta_guard(proposta) do
      escolhas = Store.escolhas(repo, tekoa_id, proposta.id)
      moradores = MaracaStore.count_moradores(repo, tekoa_id)
      resultado = Policy.tally(escolhas, moradores)

      Store.update(repo, Proposta.fechar_changeset(proposta, resultado))
    end
  end

  @doc """
  Reclama a execucao do ato aprovado, uma unica vez. Devolve {:ok, proposta}
  com `executado_em` preenchido quando a reclamacao e primeira, e
  {:error, :already_executed} quando o ato ja rodou. A execucao em si (o
  efeito do ato) e do produto, que usa este token.
  """

  ## Internos

  @spec executar(Ecto.Repo.t(), integer(), Proposta.t()) ::
          {:ok, Proposta.t()} | {:error, :already_executed | term()}
  def executar(repo, tekoa_id, %Proposta{id: id}) do
    with {:ok, proposta} <- proposta_atual(repo, tekoa_id, id),
         :ok <- aprovada_guard(proposta),
         {:ok, _agora} <- Store.claim_execucao(repo, tekoa_id, proposta.id, agora()) do
      if nova_proposta = Store.get_proposta_por_id(repo, tekoa_id, proposta.id),
        do: {:ok, nova_proposta},
        else: {:error, :not_found}
    end
  end

  @doc "As propostas de uma Tekoa, mais recentes primeiro. Opcoes: `:status`, `:tipo`, `:limit`."
  @spec propostas(Ecto.Repo.t(), integer(), keyword()) :: [Proposta.t()]
  def propostas(repo, tekoa_id, opts \\ []), do: Store.propostas(repo, tekoa_id, opts)

  @doc "Os votos de uma proposta, do primeiro ao ultimo."
  @spec votos(Ecto.Repo.t(), integer(), Proposta.t()) :: [map()]
  def votos(repo, tekoa_id, %Proposta{} = proposta), do: Store.votos(repo, tekoa_id, proposta.id)

  defp mesma_tekoa(%Scope{tekoa: %{id: tekoa_id}}, %Proposta{tekoa_id: proposta_tekoa_id})
       when tekoa_id == proposta_tekoa_id, do: :ok

  defp mesma_tekoa(_scope, _proposta), do: {:error, :cross_tekoa}

  # Rele a proposta dentro da Tekoa: o status pode ter mudado desde o struct
  # em maos (outra janela votou, fechou, executou).
  defp proposta_atual(repo, tekoa_id, proposta_id) do
    case Store.get_proposta_por_id(repo, tekoa_id, proposta_id) do
      %Proposta{} = proposta -> {:ok, proposta}
      nil -> {:error, :not_found}
    end
  end

  defp aberta_guard(%Proposta{status: :aberta}), do: :ok
  defp aberta_guard(_proposta), do: {:error, :invalid_status}

  defp prazo_guard(%Proposta{fecha_em: fecha_em}) do
    if Policy.expired?(fecha_em, DateTime.utc_now()), do: {:error, :expirada}, else: :ok
  end

  defp aprovada_guard(%Proposta{status: :aprovada}), do: :ok
  defp aprovada_guard(_proposta), do: {:error, :invalid_status}

  defp fetch_fecha_em(opts) do
    case Keyword.fetch(opts, :fecha_em) do
      {:ok, %DateTime{} = fecha_em} -> {:ok, DateTime.truncate(fecha_em, :second)}
      :error -> {:error, :missing_fecha_em}
    end
  end

  defp agora, do: DateTime.truncate(DateTime.utc_now(), :second)
end
