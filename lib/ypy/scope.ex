defmodule Ypy.Scope do
  @moduledoc """
  Identidade da acao: quem age (`ava`) e em qual comunidade (`tekoa`).

  Todo verbo do kernel com escopo recebe um `%Ypy.Scope{}` como argumento.
  Nenhuma operacao de dominio acontece sem saber a Tekoa: a leitura respeita
  zona e concessao (RFC_003 D2) e todo `WHERE` carrega `tekoa_id` explicito.
  """

  @enforce_keys [:ava, :tekoa]
  defstruct [:ava, :tekoa]

  @type t :: %__MODULE__{ava: term(), tekoa: term()}
end
