defmodule TainaWeb.API.Params do
  @moduledoc """
  Os campos de corpo que mais de um controller da API le (RFC_005 secao 9).

  Por enquanto, so o rotulo do aparelho: ele entra em todo fluxo que termina
  com um token de dispositivo (login, aceite de convite, redefinicao de senha)
  e o tratamento e o mesmo em todos.
  """

  # O rotulo do aparelho vem do cliente (ex.: "iPhone da Ana"); sem ele, um nome
  # generico, porque o campo e obrigatorio (1 a 80) e a lista precisa de nome.
  # Trunca em 80: um rotulo longo nao pode derrubar o login inteiro.
  def device_name(params) do
    case params["device_name"] do
      name when is_binary(name) ->
        case String.trim(name) do
          "" -> "Dispositivo"
          trimmed -> String.slice(trimmed, 0, 80)
        end

      _ ->
        "Dispositivo"
    end
  end
end
