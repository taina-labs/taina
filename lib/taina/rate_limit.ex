defmodule Taina.RateLimit do
  @moduledoc """
  Limitador de taxa em memória (ETS), via Hammer.

  Hoje serve só ao login (`Taina.Maraca.authenticate/3`), travando força bruta
  de credenciais por `(tekoa, email)`. É um processo único na árvore de
  supervisão (ver `Taina.Application`); o estado vive em ETS local ao nó — um nó
  BEAM atende uma comunidade inteira (RFC 002), então não há coordenação entre
  nós a fazer.

  Use `hit/3`: devolve `{:allow, contagem}` enquanto houver folga na janela e
  `{:deny, ms_ate_liberar}` quando o limite estoura.
  """

  use Hammer, backend: :ets
end
