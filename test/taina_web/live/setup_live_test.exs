defmodule TainaWeb.SetupLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  test "instância já inicializada redireciona para o login", %{conn: conn} do
    tekoa_fixture()

    assert {:error, {:redirect, %{to: "/login"}}} = live(conn, ~p"/setup")
  end

  test "wizard percorre os três passos validando cada um", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/setup")

    assert html =~ "Tainá"
    assert html =~ "Passo 1 de 3"

    # passo 1: nome vazio trava
    html = lv |> element("form") |> render_submit(%{"setup" => %{"community_name" => "  "}})
    assert html =~ "dê um nome à comunidade"

    html = lv |> element("form") |> render_submit(%{"setup" => %{"community_name" => "Quilombo do Café"}})
    assert html =~ "Crie a conta de quem cuida"

    # passo 2: senha curta trava
    html = lv |> element("form") |> render_submit(%{"setup" => %{"username" => "ana", "password" => "curta"}})
    assert html =~ "pelo menos 8 caracteres"

    html =
      lv
      |> element("form")
      |> render_submit(%{"setup" => %{"username" => "ana", "password" => "frase-longa-segura"}})

    # passo 3: resumo + form final apontando para o POST /setup
    assert html =~ "Onde guardar os arquivos"
    assert html =~ "Quilombo do Café, zelador(a) ana, disco interno"
    assert has_element?(lv, ~s(form[action="/setup"]))
    assert has_element?(lv, ~s(input[name="setup[password_confirmation]"]))
  end

  test "voltar regride o passo", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/setup")

    lv |> element("form") |> render_submit(%{"setup" => %{"community_name" => "Aldeia"}})
    html = lv |> element("button[phx-click=back]") |> render_click()

    assert html =~ "Passo 1 de 3"
  end
end
