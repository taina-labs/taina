defmodule TainaWeb.InviteFlowTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Maraca

  setup do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa)
    %{tekoa: tekoa, zelador: zelador}
  end

  test "morador comum não acessa a tela de convite", %{conn: conn, tekoa: tekoa} do
    morador = active_ava_fixture(tekoa)

    assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in(morador) |> live(~p"/membros/convidar")
  end

  test "zelador gera convite com link + QR, sem e-mail", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros/convidar")

    html = lv |> element("form") |> render_submit(%{})

    assert html =~ "/convite/"
    assert html =~ "<svg"
    assert html =~ "Copiar link"
  end

  test "convite aceito vira conta logada", %{conn: conn, zelador: zelador, tekoa: tekoa} do
    {:ok, invited} = Maraca.invite_user(zelador, tekoa)
    token = invited.invite_token

    # a tela de aceite renderiza com o token na URL
    {:ok, _lv, html} = live(conn, ~p"/convite/#{token}")
    assert html =~ "Você foi convidado!"

    # o POST cria a conta e entra
    conn =
      post(conn, ~p"/convite/#{token}", %{
        "account" => %{
          "username" => "joao",
          "display_name" => "João Mendes",
          "password" => "frase-longa-segura",
          "password_confirmation" => "frase-longa-segura"
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
          "password" => "frase-longa-segura",
          "password_confirmation" => "frase-longa-segura"
        }
      })

    assert redirected_to(conn) == ~p"/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "expirou"
  end
end
