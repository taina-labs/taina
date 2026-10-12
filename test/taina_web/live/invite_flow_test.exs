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

    assert {:error, {:redirect, %{to: "/"}}} = conn |> log_in(morador) |> live(~p"/membros/convidar")
  end

  test "zelador gera convite com link + QR, sem e-mail", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros/convidar")

    html = lv |> element("form") |> render_submit(%{})

    assert html =~ "/convite/"
    assert html =~ "<svg"
    assert html =~ "Copiar link"
  end

  test "aviso honesto quando o navegador não consegue copiar o link", %{conn: conn, zelador: zelador} do
    {:ok, lv, _html} = conn |> log_in(zelador) |> live(~p"/membros/convidar")

    lv |> element("form") |> render_submit(%{})

    # O hook Clipboard cai aqui em origem insegura (http://taina.local, sem
    # navigator.clipboard). Antes este evento derrubava a LiveView.
    html = render_hook(lv, "copy-failed", %{})

    assert html =~ "Selecione o link e copie com a mão."
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

  test "token desconhecido mostra o estado de convite expirado em vez do formulário", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/convite/nao-existe")

    assert html =~ "Este convite expirou ou já foi usado"
    assert html =~ "Ir para o login"
    refute html =~ "Criar conta"
  end

  test "convite expirado mostra o estado de beco sem saída antes de preencher o formulário", %{
    conn: conn,
    zelador: zelador,
    tekoa: tekoa
  } do
    {:ok, invited} = Maraca.invite_user(zelador, tekoa)

    eight_days_ago = DateTime.shift(DateTime.utc_now(), day: -8)

    Repo.with_tekoa(tekoa.public_id, fn ->
      {:ok,
       invited
       |> Ecto.Changeset.change(invite_sent_at: eight_days_ago)
       |> Repo.update!()}
    end)

    {:ok, _lv, html} = live(conn, ~p"/convite/#{invited.invite_token}")

    assert html =~ "Este convite expirou ou já foi usado"
    refute html =~ "account[password]"
  end
end
