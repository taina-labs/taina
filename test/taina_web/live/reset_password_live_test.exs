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

  test "link válido renderiza o formulário de redefinição", %{conn: conn, zelador: zelador, member: member, tekoa: tekoa} do
    {:ok, %{token: token}} = Maraca.mint_reset_link(Scope.new(zelador, tekoa), member)

    {:ok, _lv, html} = live(conn, ~p"/redefinir/#{token}")

    assert html =~ "Redefinir senha"
    assert html =~ "Salvar nova senha"
  end

  test "token desconhecido mostra o estado de link expirado em vez do formulário", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/redefinir/nao-existe")

    assert html =~ "Este link expirou ou já foi usado"
    assert html =~ "Ir para o login"
    refute html =~ "Salvar nova senha"
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

    assert html =~ "Este link expirou ou já foi usado"
    refute html =~ "reset_password"
  end
end
