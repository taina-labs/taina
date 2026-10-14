defmodule TainaWeb.ErrorJSON do
  @moduledoc """
  Erros de JSON que o endpoint levanta antes de chegar a um controller (rota
  inexistente, corpo grande demais): mesmo envelope da API (RFC_005 D6), para o
  cliente ter um so decoder de erro.
  """

  @codes %{
    "400.json" => "invalid_action",
    "404.json" => "not_found",
    "413.json" => "payload_too_large",
    "500.json" => "internal_error"
  }

  @messages %{
    "invalid_action" => "Essa ação não vale aqui.",
    "not_found" => "Não encontramos isso aqui.",
    "payload_too_large" => "O envio passou do tamanho permitido.",
    "internal_error" => "Algo falhou do nosso lado. Tente de novo."
  }

  def render(template, _assigns) do
    code = Map.get(@codes, template, "internal_error")
    %{"error" => %{"code" => code, "message" => @messages[code]}}
  end
end
