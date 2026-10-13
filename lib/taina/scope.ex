defmodule Taina.Scope do
  @moduledoc """
  Identidade da requisição atual: quem está agindo (`ava`) e em qual
  comunidade (`tekoa`).

  Constrói o scope do kernel (`Ypy.Scope`), a struct que os contextos Ypy
  recebem. Todo context público do Tainá recebe um scope como primeiro
  argumento (padrão de scopes do Phoenix 1.8): nenhuma operação de domínio
  acontece sem saber a Tekoa.
  """

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa

  @doc """
  Constrói um scope a partir de um Ava com a Tekoa pré-carregada.

  A associação `tekoa` do Ava precisa estar pré-carregada (`%Tekoa{}`); o
  caminho normal de sessão já devolve assim (`Maraca.get_session_user/1`).
  Sem o preload, `ava.tekoa` é `%Ecto.Association.NotLoaded{}` e `for_ava/1`
  levanta `ArgumentError` apontando o preload, em vez de um
  `FunctionClauseError` sem pista.
  """
  @spec for_ava(Ava.t()) :: Ypy.Scope.t()
  def for_ava(%Ava{tekoa: %Tekoa{} = tekoa} = ava) do
    new(ava, tekoa)
  end

  def for_ava(%Ava{} = ava) do
    raise ArgumentError,
          "Scope.for_ava/1 requer a associação :tekoa do Ava pré-carregada. " <>
            "Pré-carregue com Repo.preload(ava, :tekoa) dentro de Repo.with_tekoa/2 " <>
            "ou use Maraca.get_session_user/1, que já devolve o Ava com a Tekoa. " <>
            "Recebido: #{inspect(ava.tekoa)}"
  end

  @doc """
  Constrói um scope a partir de um Ava e uma Tekoa explícitos.
  """
  def new(%Ava{} = ava, %Tekoa{} = tekoa) do
    %Ypy.Scope{ava: ava, tekoa: tekoa}
  end
end
