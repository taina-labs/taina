defmodule TainaWeb.MembersLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  setup do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa, %{username: "ana", display_name: "Ana Oliveira"})
    member = active_ava_fixture(tekoa, %{username: "joao", display_name: "João Mendes"})
    %{tekoa: tekoa, zelador: zelador, member: member}
  end

  test "lista moradores com papel e estado", %{conn: conn, zelador: zelador} do
    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/membros")

    assert html =~ "Ana Oliveira"
    assert html =~ "João Mendes"
    assert html =~ "Você"
    assert html =~ "2 pessoas"
  end

  test "busca filtra a lista", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros")

    html = lv |> element("form.search") |> render_change(%{"query" => "joão"})

    assert html =~ "João Mendes"
    refute html =~ "Ana Oliveira"
  end

  test "zelador gera link de redefinição para um morador", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros")

    html = lv |> element(~s([phx-click="reset-link"][phx-value-id])) |> render_click()

    assert html =~ "Link de redefinição de senha"
    assert html =~ "/redefinir/"
  end

  test "morador comum não vê atalho de convite", %{conn: conn, member: member} do
    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/membros")

    refute html =~ "/membros/convidar"
  end

  test "zelador muda o papel de um morador", %{conn: conn, zelador: zelador, member: member} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros")

    html = render_click(lv, "set-role", %{"id" => member.public_id, "role" => "zelador"})

    assert html =~ "Papel atualizado."
  end

  test "zelador desativa e reativa um morador", %{conn: conn, zelador: zelador, member: member} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros")

    html = render_click(lv, "deactivate", %{"id" => member.public_id})
    assert html =~ "Conta desativada"

    html = render_click(lv, "reactivate", %{"id" => member.public_id})
    assert html =~ "Conta reativada."
  end

  test "não deixa desativar o último zelador", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros")

    html = render_click(lv, "deactivate", %{"id" => zelador.public_id})

    assert html =~ "pelo menos um zelador ativo"
  end

  test "morador comum não vê ações de conta", %{conn: conn, member: member} do
    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/membros")

    refute html =~ "Ações da conta"
  end
end
