defmodule TainaWeb.StorageLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira
  alias Ypy.Maraca.Tekoa

  setup do
    tekoa = tekoa_fixture()
    %{tekoa: tekoa, admin: zelador_fixture(tekoa), member: active_ava_fixture(tekoa)}
  end

  test "mostra uso e legenda por tipo", %{conn: conn, member: member} do
    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/armazenamento")

    assert html =~ "Uso por tipo"
    assert html =~ "Fotos"
    assert html =~ "Documentos"
    # Honestidade da cota: apagar não libera espaço na hora, a lixeira segura
    # os bytes por 30 dias.
    assert html =~ "30 dias"
    # membro comum não edita cota
    refute html =~ "Cota da comunidade"
  end

  test "não mostra resto negativo quando a cota fica abaixo do uso", %{
    conn: conn,
    member: member,
    tekoa: tekoa
  } do
    scope = Scope.new(member, tekoa)
    {:ok, _file} = Ybira.upload(scope, tmp_upload_fixture(String.duplicate("x", 100), "grande.txt"))

    # A cota pode ser definida abaixo do uso atual; o que falta, na tela, é
    # zero, nunca número negativo.
    tekoa = Repo.get!(Tekoa, tekoa.id, skip_tekoa_id: true)

    {:ok, _} =
      Repo.update(Tekoa.changeset(tekoa, %{storage_quota_bytes: 10}), skip_tekoa_id: true)

    {:ok, _lv, html} = conn |> log_in(member) |> live(~p"/armazenamento")

    assert html =~ "0 B livres"
    refute html =~ "-90"
  end

  test "admin atualiza a cota da comunidade", %{conn: conn, admin: admin} do
    {:ok, lv, html} = conn |> log_in(admin) |> live(~p"/armazenamento")

    assert html =~ "Cota da comunidade"

    lv |> element("button[phx-click=toggle-quota-modal]") |> render_click()
    lv |> form("#quota-modal form") |> render_submit(%{"quota" => %{"gigabytes" => "10"}})

    assert render(lv) =~ "10 GB"
  end
end
