defmodule TainaWeb.ResetPasswordLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Repo
  alias Taina.Scope

  setup do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa)
    member = active_ava_fixture(tekoa, %{username: "maria"})
    %{tekoa: tekoa, zelador: zelador, member: member}
  end

  test "link válido renderiza o formulário de redefinição, uma senha só", %{
    conn: conn,
    zelador: zelador,
    member: member,
    tekoa: tekoa
  } do
    {:ok, %{token: token}} = Maraca.mint_reset_link(Scope.new(zelador, tekoa), member)

    {:ok, lv, html} = live(conn, ~p"/redefinir/#{token}")

    # O "Mostrar" cobre a conferência: sem o segundo campo (spec 6.5).
    assert html =~ "Redefinir senha"
    assert html =~ "Crie uma senha nova para voltar a entrar."
    assert html =~ "Use uma frase longa que só você lembra."
    assert html =~ "Salvar nova senha"
    refute html =~ "account[password_confirmation]"
    assert has_element?(lv, ~s(form#reset-form))
  end

  test "token desconhecido mostra o estado de link expirado em vez do formulário", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/redefinir/nao-existe")

    # O board "Redefinir / expirado" é um cartão de erro, não um form.
    assert html =~ "Este link expirou."
    assert has_element?(lv, ~s(.error-card))
    assert has_element?(lv, ~s(button), "Voltar")
    refute html =~ "Salvar nova senha"
  end

  test "o cartão vencido oferece falar com quem cuida, sem corpo inventado", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/redefinir/nao-existe")

    assert has_element?(lv, ".error-card button", "Falar com quem cuida")

    lv |> element(".error-card button", "Falar com quem cuida") |> render_click()

    assert render(lv) =~ "Quem cuida da sua comunidade gera um link novo"
  end

  test "o Voltar do cartão leva para o login", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/redefinir/nao-existe")

    assert {:error, {:live_redirect, %{to: "/login"}}} =
             lv |> element(~s(.error-card button), "Voltar") |> render_click()
  end

  test "link expirado mostra o estado de beco sem saída antes de preencher o formulário", %{
    conn: conn,
    zelador: zelador,
    member: member,
    tekoa: tekoa
  } do
    {:ok, %{ava: with_token, token: token}} = Maraca.mint_reset_link(Scope.new(zelador, tekoa), member)

    two_hours_ago = DateTime.shift(DateTime.utc_now(), hour: -2)

    Repo.with_tekoa(tekoa.public_id, fn ->
      {:ok,
       with_token
       |> Ecto.Changeset.change(reset_sent_at: DateTime.truncate(two_hours_ago, :second))
       |> Repo.update!()}
    end)

    # O link real, já vencido: o estado de beco sem saída é o mesmo do token
    # desconhecido, mas o teste prova o do token que um dia valeu.
    {:ok, _lv, html} = live(conn, ~p"/redefinir/#{token}")

    assert html =~ "Este link expirou."
    refute html =~ "reset_password"
  end
end
