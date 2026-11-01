defmodule TainaWeb.GalleryLiveTest do
  @moduledoc """
  A Galeria (docs/web-revamp-spec.md 6.3): um teste por estado dos boards
  (grade padrão, grade vazio, grade carregando, linha padrão, visualizador
  padrão e visualizador erro), mais os comportamentos que a tela preserva:
  paginação por cursor, filtro de zona na URL e os fluxos do visualizador
  (navegação, detalhes, publicar, excluir).
  """

  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira
  alias TainaWeb.GalleryLive

  setup do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    scope = Scope.new(ava, tekoa)

    {:ok, first} = Ybira.upload(scope, tmp_image_fixture(filename: "primeira.jpg"))
    {:ok, second} = Ybira.upload(scope, tmp_image_fixture(filename: "segunda.jpg"))

    %{scope: scope, ava: ava, first: first, second: second}
  end

  # Board "Grade / padrao": fotos com thumbnail, FAB Enviar e abas como rotas.
  test "grade padrão: fotos com thumbnail, FAB Enviar e abas como rotas", %{
    conn: conn,
    ava: ava,
    first: first,
    second: second
  } do
    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria")

    assert has_element?(lv, ".photo-grid")
    assert html =~ "/files/#{first.rkey}/thumbnail/sm"
    assert html =~ "/files/#{second.rkey}/thumbnail/sm"

    # o conjunto inteiro cabe na primeira página: a linha do total do board aparece
    assert html =~ "2 fotos"

    # FAB "Enviar" leva ao envio (toda foto nasce na casa); o mesmo "Enviar"
    # mora no cabeçalho do desktop (a troca é do CSS, os dois ficam no DOM)
    assert has_element?(lv, ~s(.fab[href="/documentos/enviar?return_to=%2Fgaleria"]), "Enviar")
    assert has_element?(lv, ~s(.service-header a[href="/documentos/enviar?return_to=%2Fgaleria"]))

    # abas são rotas na barra de serviço, não segmented
    assert has_element?(lv, ~s(.service-tab-bar__item[href="/galeria"]), "Grade")
    assert has_element?(lv, ~s(.service-tab-bar__item[href="/galeria/linha-do-tempo"]), "Linha do tempo")
    assert has_element?(lv, ~s(.service-tab-bar__item[aria-current="page"]), "Grade")
    refute has_element?(lv, ".segmented")

    # o board não desenha badge de zona no tile
    refute has_element?(lv, ".photo-grid__tag")
  end

  # Board "Grade / vazio": estado vazio honesto com a saída para enviar.
  test "grade vazio: estado honesto com a saída para enviar", %{
    conn: conn,
    ava: ava,
    scope: scope,
    first: first,
    second: second
  } do
    {:ok, _} = Ybira.delete_file(scope, first.rkey)
    {:ok, _} = Ybira.delete_file(scope, second.rkey)

    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria")

    assert has_element?(lv, ".empty-state", "Ainda não há fotos")
    assert html =~ "Quando alguém enviar uma foto, ela aparece aqui para toda a comunidade."
    assert has_element?(lv, ~s(.empty-state a[href="/documentos/enviar?return_to=%2Fgaleria"]), "Enviar uma foto")
    refute has_element?(lv, ".photo-grid__item")
    refute has_element?(lv, ".skeleton")
  end

  # Board "Grade / carregando": esqueleto no formato do alvo, sem spinner. A
  # carga em si é síncrona no handle_params, então o estado se exercita no
  # componente puro (a mesma peça que a tela renderiza), como no hub.
  test "grade carregando: esqueleto no formato do alvo, sem spinner", %{scope: scope} do
    html =
      render_component(&GalleryLive.gallery_content/1, %{
        g: %{
          current_scope: scope,
          live_action: :grid,
          zona: :tudo,
          next_cursor: nil,
          counts: nil,
          photo_ids: [],
          loaded: false,
          grid_error: false,
          timeline_cursor: nil,
          timeline_empty: true,
          timeline_error: false,
          current: nil,
          viewer_error: false,
          viewer_rkey: nil,
          show_confirm: false,
          show_details: false,
          show_zona: false,
          streams: %{photos: [], timeline_groups: []}
        }
      })

    assert html =~ "skeleton--photo-grid"
    assert html =~ "skeleton__tile"
    refute html =~ "spinner"
  end

  # Board "Linha / padrao": grupos por dia com o dia escrito ("4 de outubro"),
  # segunda aba selecionada, o mesmo FAB; sem contagem por grupo no board.
  test "linha padrão: grupos por dia com o dia escrito, segunda aba selecionada", %{
    conn: conn,
    ava: ava
  } do
    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria/linha-do-tempo")

    assert has_element?(lv, ".photo-grid")
    assert html =~ dia_escrito(Date.utc_today())
    assert has_element?(lv, ~s(.service-tab-bar__item[aria-current="page"]), "Linha do tempo")
    refute html =~ "2 fotos"
    assert has_element?(lv, ~s(.fab[href="/documentos/enviar?return_to=%2Fgaleria%2Flinha-do-tempo"]), "Enviar")
  end

  # Board "Visualizador / padrao": fullscreen, media com FullSwap, navegação
  # pelo ViewerNav, legenda com o nome e o contador.
  test "visualizador navega entre fotos", %{conn: conn, ava: ava, first: first, second: second} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/galeria")

    # abre a mais recente (segunda) a partir da grade
    html = lv |> element(~s(a[href="/galeria/#{second.rkey}"])) |> render_click()
    assert html =~ "1 de 2"
    assert html =~ "segunda.jpg"
    assert has_element?(lv, ~s(.viewer[phx-hook="ViewerNav"]))
    assert has_element?(lv, "#viewer-full-swap")

    # próxima = mais antiga
    lv |> element("button.viewer__nav--next") |> render_click()
    assert_patch(lv, ~p"/galeria/#{first.rkey}")
    assert render(lv) =~ "primeira.jpg"

    # fechar volta para a grade
    lv |> element("button[phx-click=close]") |> render_click()
    assert_patch(lv, ~p"/galeria")
  end

  test "fechar uma foto aberta pela linha do tempo volta para essa aba", %{
    conn: conn,
    ava: ava,
    second: second
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/galeria/linha-do-tempo")

    lv |> element(~s(a[href="/galeria/#{second.rkey}"])) |> render_click()
    assert_patch(lv, ~p"/galeria/#{second.rkey}")
    assert has_element?(lv, "#timeline-groups")
    refute has_element?(lv, "#photo-grid")

    lv |> element("button[phx-click=close]") |> render_click()
    assert_patch(lv, ~p"/galeria/linha-do-tempo")
  end

  # Board "Visualizador / erro": o casco fica de pé com o cartão calmo
  # ("Tentar de novo" e "Falar com quem cuida") e a frase honesta; sem trilha
  # carregada (link direto), o contador cala em vez de inventar "1 de 1".
  test "visualizador erro: casco com cartão calmo e frase honesta", %{conn: conn, ava: ava} do
    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria/rkey-que-nao-existe")

    assert has_element?(lv, ".viewer")
    assert html =~ "Não conseguimos abrir esta foto"
    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert has_element?(lv, ".error-card", "Tentar de novo")
    assert has_element?(lv, ".error-card", "Falar com quem cuida")
    refute html =~ "1 de 1"

    # "Tentar de novo" mantém o estado honesto enquanto a foto não abre
    lv |> element(".error-card button", "Tentar de novo") |> render_click()
    assert render(lv) =~ "Não conseguimos abrir esta foto"

    # fechar volta para a grade
    lv |> element("#viewer-close") |> render_click()
    assert_patch(lv, ~p"/galeria")
  end

  test "foto na casa de outro morador leva para a tela de pedir acesso", %{conn: conn, ava: ava, scope: scope} do
    outra = active_ava_fixture(scope.tekoa, %{username: "outra"})
    {:ok, file} = Ybira.upload(Scope.new(outra, scope.tekoa), tmp_image_fixture(filename: "particular.jpg"))

    assert {:error, {_kind, %{to: to}}} = conn |> log_in(ava) |> live(~p"/galeria/#{file.rkey}")
    assert to == "/documentos/#{file.rkey}"
  end

  # A linha do total do board nomeia fotos e vídeos, separados por vírgula.
  test "a linha do total nomeia fotos e vídeos", %{conn: conn, ava: ava, scope: scope} do
    {:ok, _video} = Ybira.upload(scope, tmp_video_fixture("festa.mp4"))

    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria")

    assert html =~ "2 fotos, 1 vídeo"
    # vídeo sem thumbnail: o tile mostra o marcador de play
    assert has_element?(lv, ".photo-grid__video")
  end

  test "com páginas pela frente, a linha do total diz o conjunto inteiro", %{
    conn: conn,
    ava: ava,
    scope: scope
  } do
    # o limite da grade é 50: uma página cheia deixa cursor
    for n <- 1..50 do
      {:ok, _} = Ybira.upload(scope, tmp_image_fixture(filename: "extra-#{n}.jpg"))
    end

    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria")

    assert has_element?(lv, "#grid-load-more")
    # o total é agregado no banco (Jaci.count_media/2): não depende da página
    assert html =~ "52 fotos"
  end

  # --- zonas casa/praca (RFC_003 D1/D2) ---

  describe "zonas casa/praca" do
    test "o padrão é o conjunto legível inteiro, sem filtro desenhado", %{
      conn: conn,
      ava: ava,
      scope: scope,
      first: first
    } do
      {:ok, _} = Ybira.publicar_file(scope, first.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria")

      # a publicada e a da casa, lado a lado; o board não desenha badge de
      # zona no tile nem filtro de zona na tela
      assert html =~ "primeira.jpg"
      assert html =~ "segunda.jpg"
      refute has_element?(lv, ".photo-grid__tag")
      refute has_element?(lv, ".segmented")
    end

    test "?zona=casa mostra só o que está na casa; ?zona=praca, só as publicadas", %{
      conn: conn,
      ava: ava,
      scope: scope,
      first: first
    } do
      {:ok, _} = Ybira.publicar_file(scope, first.rkey)

      {:ok, casa_lv, casa_html} = conn |> log_in(ava) |> live(~p"/galeria?zona=casa")

      refute casa_html =~ "primeira.jpg"
      assert casa_html =~ "segunda.jpg"
      assert has_element?(casa_lv, ~s(.fab[href="/documentos/enviar?return_to=%2Fgaleria%3Fzona%3Dcasa"]))

      {:ok, _lv, praca_html} = conn |> log_in(ava) |> live(~p"/galeria?zona=praca")

      assert praca_html =~ "primeira.jpg"
      refute praca_html =~ "segunda.jpg"
    end

    test "a linha do tempo acompanha o filtro da zona", %{conn: conn, ava: ava, scope: scope, first: first} do
      {:ok, _} = Ybira.publicar_file(scope, first.rkey)

      {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/galeria/linha-do-tempo?zona=praca")

      assert has_element?(lv, ~s(.fab[href="/documentos/enviar?return_to=%2Fgaleria%2Flinha-do-tempo%3Fzona%3Dpraca"]))

      assert html =~ "primeira.jpg"
      refute html =~ "segunda.jpg"
    end
  end

  # O formato do board ("4 de outubro"): mesma regra do group_title/1 da tela.
  defp dia_escrito(date) do
    meses = ~w(janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro)
    "#{date.day} de #{Enum.at(meses, date.month - 1)}"
  end
end
