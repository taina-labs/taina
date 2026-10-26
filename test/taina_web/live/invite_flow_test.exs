defmodule TainaWeb.InviteFlowTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Repo

  setup do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa)
    %{tekoa: tekoa, zelador: zelador}
  end

  test "morador comum não acessa a tela de convite", %{conn: conn, tekoa: tekoa} do
    morador = active_ava_fixture(tekoa)

    assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in(morador) |> live(~p"/moradores/convidar")
  end

  test "papel: RadioCards do board com o que cada papel pode", %{conn: conn, zelador: zelador} do
    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/moradores/convidar")

    assert has_element?(lv, ".radio-card", "Morador")
    assert has_element?(lv, ".radio-card", "Zelador")
    assert html =~ "Vê a praça e ganha uma casa própria."
    assert html =~ "Cuida da máquina: disco, backups e convites. Para abrir uma casa, pede como todo mundo."
    assert has_element?(lv, ~s(#invite-form button[type="submit"]), "Criar convite")
    assert html =~ "Você cria convites só quando quiser. Dá para cancelar depois."
  end

  test "zelador gera convite com link + QR, sem e-mail", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores/convidar")

    html = lv |> element("form") |> render_submit(%{})

    assert html =~ "/convite/"
    assert html =~ "<svg"
    assert html =~ "Copiar link"
    assert html =~ "Convite criado. Envie o link para a pessoa."
    assert html =~ "O convite vale por 7 dias."
  end

  test "aviso honesto quando o navegador não consegue copiar o link", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/moradores/convidar")

    lv |> element("form") |> render_submit(%{})

    # O hook Clipboard cai aqui em origem insegura (http://taina.local, sem
    # navigator.clipboard). Antes este evento derrubava a LiveView.
    html = render_hook(lv, "copy-failed", %{})

    assert html =~ "Selecione o link e copie com a mão."
  end

  test "convite aceito vira conta logada, sem o campo de confirmar senha", %{
    conn: conn,
    zelador: zelador,
    tekoa: tekoa
  } do
    {:ok, %{token: token}} = Maraca.invite_user(zelador, tekoa)

    # a tela de aceite renderiza com o token na URL, uma senha só (o
    # "Mostrar" cobre a conferência, spec 6.5)
    {:ok, lv, html} = live(conn, ~p"/convite/#{token}")

    assert html =~ "Você recebeu um convite"
    assert html =~ tekoa.name
    refute html =~ "account[password_confirmation]"
    assert has_element?(lv, ~s(a[href="/login"]), "Entrar")

    # o POST cria a conta e entra
    conn =
      post(conn, ~p"/convite/#{token}", %{
        "account" => %{
          "username" => "joao",
          "display_name" => "João Mendes",
          "password" => "frase-longa-segura"
        }
      })

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :ava_id)
  end

  test "token inválido no aceite volta para o login com aviso", %{conn: conn} do
    conn =
      post(conn, ~p"/convite/token-invalido", %{
        "account" => %{
          "username" => "joao",
          "password" => "frase-longa-segura"
        }
      })

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expirou"
  end

  test "token desconhecido mostra o cartão de convite inválido em vez do formulário", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/convite/nao-existe")

    # O board "Convite / expirado" é um cartão de erro com a saída para o
    # login embaixo.
    assert html =~ "Este convite não é mais válido."
    assert has_element?(lv, ~s(.error-card))
    assert has_element?(lv, ~s(a[href="/login"]), "Voltar para entrar")
    refute html =~ "Criar conta"
  end

  test "o cartão vencido oferece falar com quem cuida, sem corpo inventado", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/convite/nao-existe")

    assert has_element?(lv, ".error-card button", "Falar com quem cuida")

    lv |> element(".error-card button", "Falar com quem cuida") |> render_click()

    assert render(lv) =~ "Quem cuida da sua comunidade gera um convite novo"
  end

  test "o Voltar do cartão leva para o login", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/convite/nao-existe")

    assert {:error, {:live_redirect, %{to: "/login"}}} =
             lv |> element(~s(.error-card button), "Voltar") |> render_click()
  end

  test "convite expirado mostra o estado de beco sem saída antes de preencher o formulário", %{
    conn: conn,
    zelador: zelador,
    tekoa: tekoa
  } do
    {:ok, %{ava: invited, token: token}} = Maraca.invite_user(zelador, tekoa)

    eight_days_ago = DateTime.shift(DateTime.utc_now(), day: -8)

    Repo.with_tekoa(tekoa.public_id, fn ->
      {:ok,
       invited
       |> Ecto.Changeset.change(invite_sent_at: DateTime.truncate(eight_days_ago, :second))
       |> Repo.update!()}
    end)

    {:ok, _lv, html} = live(conn, ~p"/convite/#{token}")

    assert html =~ "Este convite não é mais válido."
    assert html =~ "Voltar para entrar"
    refute html =~ "account[password]"
  end
end
