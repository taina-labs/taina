defmodule TainaWeb.RouterTest do
  @moduledoc """
  A tabela de rotas da spec 6 montando de verdade (aceitação de W2.2): para
  cada rota live autenticada, `{:ok, _view, _html}`, para um zelador e um
  morador. As rotas com segmento (pasta, arquivo, foto) usam registros do
  próprio papel: ler casa alheia é recusa, não é assunto de rota.
  """
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    zelador = zelador_fixture(tekoa)
    morador = active_ava_fixture(tekoa, %{username: "morador"})

    registros =
      for {papel, ava} <- [zelador: zelador, morador: morador], into: %{} do
        scope = Scope.new(ava, tekoa)
        {:ok, folder} = Ybira.create_folder(scope, %{name: "Atas"})
        {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "estatuto.txt"))
        {:ok, photo} = Ybira.upload(scope, tmp_image_fixture())

        {papel, %{folder: folder, file: file, photo: photo}}
      end

    %{registros: registros, zelador: zelador, morador: morador}
  end

  # Rotas live autenticadas da spec 6, cada uma com o registro do papel.
  defp rotas_live(%{folder: folder, file: file, photo: photo}) do
    [
      ~p"/",
      ~p"/documentos",
      ~p"/documentos/casa",
      ~p"/documentos/pasta/#{folder.rkey}",
      ~p"/documentos/lixeira",
      ~p"/documentos/enviar",
      ~p"/documentos/#{file.rkey}",
      ~p"/galeria",
      ~p"/galeria/linha-do-tempo",
      ~p"/galeria/#{photo.rkey}",
      ~p"/mural",
      ~p"/saude",
      ~p"/moradores",
      ~p"/armazenamento",
      ~p"/conta",
      ~p"/conta/pedidos",
      ~p"/conta/privacidade"
    ]
  end

  describe "rotas autenticadas montam" do
    test "para o zelador", ctx do
      for path <- rotas_live(ctx.registros[:zelador]) do
        assert {:ok, _view, _html} = ctx.conn |> log_in(ctx.zelador) |> live(path), path
      end
    end

    test "para o morador", ctx do
      for path <- rotas_live(ctx.registros[:morador]) do
        assert {:ok, _view, _html} = ctx.conn |> log_in(ctx.morador) |> live(path), path
      end
    end
  end

  test "convidar é do zelador: morador volta ao início", ctx do
    assert {:error, {:redirect, %{to: "/"}}} =
             ctx.conn |> log_in(ctx.morador) |> live(~p"/moradores/convidar")
  end

  # A zona é a rota: /documentos é a praça, /documentos/casa é a casa, e o
  # `?zona=` é ignorado nelas (a aba acesa na barra de abas reflete a rota).
  test "a zona vem da rota, não de query", ctx do
    conn = log_in(ctx.conn, ctx.zelador)

    {:ok, _pview, praca_html} = live(conn, ~p"/documentos")
    {:ok, praca_view, _} = live(conn, ~p"/documentos?zona=casa")
    {:ok, casa_view, _} = live(conn, ~p"/documentos/casa")

    # o ?zona=casa na rota da praca e ignorado: a aba e a praça
    assert praca_html =~ "A praça está vazia"
    assert has_element?(praca_view, ~s(.service-tab-bar__item[aria-current="page"]), "Praça")
    assert has_element?(casa_view, ~s(.service-tab-bar__item[aria-current="page"]), "Casa")
  end

  test "/convite (público, sem sessão) monta com o formulário", ctx do
    {:ok, _view, html} = live(ctx.conn, ~p"/convite")

    assert html =~ "Colar um convite"
    assert html =~ "Link ou código do convite"
  end
end
