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

    # passo 1 (board "Setup 1"): boas-vindas + nome da comunidade
    assert html =~ "Boas-vindas à Tainá"
    assert html =~ "Boas-vindas"
    assert html =~ "A estrela da manhã da sua comunidade"

    html = lv |> element("form") |> render_submit(%{"setup" => %{"community_name" => "  "}})
    assert html =~ "dê um nome à comunidade"

    html = lv |> element("form") |> render_submit(%{"setup" => %{"community_name" => "Quilombo do Café"}})

    # passo 2 (board "Setup 2"): conta de quem cuida, uma senha só (o
    # "Mostrar" cobre a conferência, spec 6.5)
    assert html =~ "Quem cuida da comunidade"
    assert html =~ "Use uma frase longa que só você lembra."
    refute html =~ "setup[password_confirmation]"

    html = lv |> element("form") |> render_submit(%{"setup" => %{"username" => "ana", "password" => "curta"}})
    assert html =~ "pelo menos 8 caracteres"

    html =
      lv
      |> element("form")
      |> render_submit(%{"setup" => %{"username" => "ana", "password" => "frase-longa-segura"}})

    # passo 3 (board "Setup 3"): o disco é fato de leitura e a escolha é do
    # limite; o resumo fecha com ela
    assert html =~ "O disco da comunidade"
    assert html =~ "escolhido na instalação"
    assert html =~ "Quanto do disco a comunidade pode usar"
    assert html =~ "O disco inteiro (recomendado)"
    assert html =~ "Quilombo do Café, quem cuida é ana. Disco interno, limite: o disco inteiro."
    assert has_element?(lv, ~s(form#setup-step-3[action="/setup"]))
    assert has_element?(lv, ~s(input[name="setup[storage_quota]"][value="inteiro"]))
    refute has_element?(lv, ~s(input[name="setup[quota_gb]"]))
  end

  test "escolhendo Um limite aparece o campo de GB e o resumo mostra o número", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/setup")

    lv |> element("form") |> render_submit(%{"setup" => %{"community_name" => "Quilombo do Café"}})
    lv |> element("form") |> render_submit(%{"setup" => %{"username" => "ana", "password" => "frase-longa-segura"}})

    html =
      lv
      |> element("form#setup-step-3")
      |> render_change(%{"setup" => %{"storage_quota" => "limite", "quota_gb" => "50"}})

    assert html =~ "Um limite"
    assert has_element?(lv, ~s(input[name="setup[quota_gb]"]))

    html = lv |> element("form#setup-step-3") |> render_submit()

    assert html =~ "Disco interno, limite: 50 GB."
  end

  test "limite sem número de GB volta para o passo 3 com o erro no campo", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/setup")

    lv |> element("form") |> render_submit(%{"setup" => %{"community_name" => "Quilombo do Café"}})
    lv |> element("form") |> render_submit(%{"setup" => %{"username" => "ana", "password" => "frase-longa-segura"}})

    lv
    |> element("form#setup-step-3")
    |> render_change(%{"setup" => %{"storage_quota" => "limite", "quota_gb" => "zero"}})

    html = lv |> element("form#setup-step-3") |> render_submit()

    assert html =~ "O limite precisa ser um número de GB maior que zero."
    assert has_element?(lv, ~s(.field--invalid input[name="setup[quota_gb]"]))
  end

  test "o passo vive na URL: ?passo=2 abre no passo certo", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/setup?passo=2")

    assert html =~ "Quem cuida da comunidade"
  end
end
