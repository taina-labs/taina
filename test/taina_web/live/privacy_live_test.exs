defmodule TainaWeb.PrivacyLiveTest do
  @moduledoc """
  Privacidade (spec 6.4, board cc1037dc-e8ab-80cc-8008-d5e239511ea7): página
  estática sob /conta, no shell page, com o copy do board.
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  setup do
    tekoa = tekoa_fixture()
    member = active_ava_fixture(tekoa, %{display_name: "Ana Oliveira"})
    %{tekoa: tekoa, member: member}
  end

  test "mostra as duas cartas do board, com o copy na íntegra", %{conn: conn, member: member} do
    {:ok, lv, html} = conn |> log_in(member) |> live(~p"/conta/privacidade")

    assert has_element?(lv, ".card h2", "Sua casa é só sua")
    assert html =~ "Ninguém abre um arquivo da sua casa sem você deixar: quem pede, você aprova ou recusa."

    assert has_element?(lv, ".card h2", "A praça é de todos")
    assert html =~ "O que você publica na praça, todo mundo lê. Publicar é um gesto seu, e dá para voltar atrás."
    assert html =~ "Casa por padrão. Praça por escolha."
  end

  test "fecha com a saída honesta do board e volta para a Conta", %{conn: conn, member: member} do
    {:ok, lv, html} = conn |> log_in(member) |> live(~p"/conta/privacidade")

    assert html =~ "Sem promessa técnica aqui: só o que acontece com os seus arquivos, em palavras simples."
    assert has_element?(lv, ~s(.page-header a[href="/conta"]))
    # sem promessa de criptografia (spec 1.6)
    refute html =~ "criptograf"
  end
end
