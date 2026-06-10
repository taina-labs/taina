defmodule Taina.Scope do
  @moduledoc """
  Identidade da requisição atual: quem está agindo (`ava`) e em qual
  comunidade (`tekoa`).

  Todo context público do Tainá recebe um `Scope` como primeiro argumento
  (padrão de scopes do Phoenix 1.8). Isso garante que nenhuma operação de
  domínio aconteça sem saber a Tekoa — e, por consequência, sem o contexto
  RLS correto via `Taina.Repo.with_tekoa/2`.
  """

  alias Taina.Maraca.Ava
  alias Taina.Maraca.Tekoa

  @enforce_keys [:ava, :tekoa]
  defstruct [:ava, :tekoa]

  @type t :: %__MODULE__{ava: Ava.t(), tekoa: Tekoa.t()}

  @doc """
  Constrói um scope a partir de um Ava com a Tekoa pré-carregada.
  """
  def for_ava(%Ava{tekoa: %Tekoa{} = tekoa} = ava) do
    %__MODULE__{ava: ava, tekoa: tekoa}
  end

  @doc """
  Constrói um scope a partir de um Ava e uma Tekoa explícitos.
  """
  def new(%Ava{} = ava, %Tekoa{} = tekoa) do
    %__MODULE__{ava: ava, tekoa: tekoa}
  end
end
