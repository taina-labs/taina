defmodule TainaWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  test "renders 404 no envelope da API" do
    assert TainaWeb.ErrorJSON.render("404.json", %{}) == %{
             "error" => %{"code" => "not_found", "message" => "Não encontramos isso aqui."}
           }
  end

  test "renders 413 com payload_too_large, nao missing_file" do
    assert TainaWeb.ErrorJSON.render("413.json", %{}) == %{
             "error" => %{
               "code" => "payload_too_large",
               "message" => "O envio passou do tamanho permitido."
             }
           }
  end

  test "renders 500 no envelope da API" do
    assert TainaWeb.ErrorJSON.render("500.json", %{}) == %{
             "error" => %{
               "code" => "internal_error",
               "message" => "Algo falhou do nosso lado. Tente de novo."
             }
           }
  end
end
