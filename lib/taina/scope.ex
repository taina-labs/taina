defmodule Taina.Scope do
  @moduledoc """
  Identidade da requisição atual: quem está agindo (`ava`) e em qual
  comunidade (`tekoa`).

  Todo context público do Tainá recebe um `Scope` como primeiro argumento
  (padrão de scopes do Phoenix 1.8). Isso garante que nenhuma operação de
  domínio aconteça sem saber a Tekoa, e, por consequência, sem o contexto
  RLS correto via `Taina.Repo.with_tekoa/2`.
  """

  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa

  @enforce_keys [:ava, :tekoa]
  defstruct [:ava, :tekoa]

  @type t :: %__MODULE__{ava: Ava.t(), tekoa: Tekoa.t()}

  @doc """
  Constrói um scope a partir de um Ava com a Tekoa pré-carregada.

  A associação `tekoa` do Ava precisa estar pré-carregada (`%Tekoa{}`). O
  caminho normal de sessão já devolve assim (`Maraca.get_session_user/1`);
  um Ava carregado por outro caminho precisa do preload antes, no contexto
  RLS adequado (`Taina.Repo.with_tekoa/2` aceita o preload; fora de contexto,
  a válvula é `skip_tekoa_id: true`):

      # Dentro de `Repo.with_tekoa/2`:
      Scope.for_ava(Repo.preload(ava, :tekoa))

      # Operação de sistema, fora de contexto:
      Scope.for_ava(Repo.preload(ava, :tekoa, skip_tekoa_id: true))

  Sem o preload, `ava.tekoa` é `%Ecto.Association.NotLoaded{}` e `for_ava/1`
  levanta `ArgumentError` apontando o preload, em vez de um
  `FunctionClauseError` sem pista.
  """
  @spec for_ava(Ava.t()) :: t()
  def for_ava(%Ava{tekoa: %Tekoa{} = tekoa} = ava) do
    %__MODULE__{ava: ava, tekoa: tekoa}
  end

  def for_ava(%Ava{} = ava) do
    raise ArgumentError,
          "Scope.for_ava/1 requer a associação :tekoa do Ava pré-carregada. " <>
            "Pré-carregue com Repo.preload(ava, :tekoa) dentro de Repo.with_tekoa/2 " <>
            "(ou Repo.preload(ava, :tekoa, skip_tekoa_id: true) numa operação de sistema), " <>
            "ou use Maraca.get_session_user/1, que já devolve o Ava com a Tekoa. " <>
            "Recebido: #{inspect(ava.tekoa)}"
  end

  @doc """
  Constrói um scope a partir de um Ava e uma Tekoa explícitos.
  """
  def new(%Ava{} = ava, %Tekoa{} = tekoa) do
    %__MODULE__{ava: ava, tekoa: tekoa}
  end
end
