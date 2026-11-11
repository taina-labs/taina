defmodule TainaWeb.SaudeLiveTest do
  @moduledoc """
  Tela "Saúde da comunidade" (docs/web-revamp-spec.md 6.4): quatro linhas de
  status (ícone e palavra juntos, nunca só cor), o rodapé que diz quem cuida
  e, para quem cuida, o passo "Fazer backup agora". Um teste por board do
  Penpot: `morador`, `zelador` e `atenção` (os três no componente puro do
  corpo, que decide cada linha do dado, mais os caminhos vivos na LiveView).
  Mutando config de backup, roda sem async.
  """

  # This module changes global application backup configuration.
  use TainaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Ecto.Changeset
  alias Taina.Maraca
  alias Taina.Repo
  alias Taina.Scope

  @gb 1024 * 1024 * 1024

  setup do
    tekoa = tekoa_fixture()
    original = Application.fetch_env!(:taina, :backup)
    on_exit(fn -> Application.put_env(:taina, :backup, original) end)

    Application.put_env(:taina, :backup, enabled: false, dir: nil)

    %{
      tekoa: tekoa,
      zelador: zelador_fixture(tekoa, %{display_name: "Ana"}),
      morador: active_ava_fixture(tekoa, %{display_name: "Bruno"})
    }
  end

  # board `morador` (componente puro: as quatro linhas em dia)
  test "board morador: quatro linhas ok e o rodapé nomeando quem cuida", %{conn: _conn} do
    html = saude_body_html(zelador?: false, zeladores: ["Ana"], backup: {:ok, %{at: now(), bytes: 100}})

    assert html =~ "ESTADO DA NUVEM"
    assert html =~ "status-line--ok"
    assert html =~ "Backup em dia"
    assert html =~ "Espaço de sobra"
    assert html =~ "Atualizações em dia"
    assert html =~ "Tudo no ar"

    # o rodapé do board: quem cuida, pelo nome, e o cuidado é da máquina
    assert html =~ "Quem cuida da nuvem é Ana. Cuida da máquina, não dos arquivos."

    # quem não cuida não ganha o botão do backup
    refute html =~ "Fazer backup agora"
  end

  # board `zelador` (componente puro: o passo de quem cuida)
  test "board zelador: 'Fazer backup agora' e a parte de quem cuida no rodapé", %{conn: _conn} do
    Application.put_env(:taina, :backup, enabled: true, dir: backup_dir())

    html = saude_body_html(zelador?: true, zeladores: ["Ana"], backup: {:ok, %{at: now(), bytes: 100}})

    assert html =~ "Fazer backup agora"
    assert html =~ "Você cuida da nuvem. O backup é a sua parte; os arquivos continuam de cada um."
  end

  # board `atenção` (componente puro: atenção e problema na mesma tela)
  test "board atenção: disco em atenção, backup falhado em problema e a saída é falar com quem cuida", %{
    conn: _conn
  } do
    html =
      saude_body_html(
        zelador?: false,
        zeladores: ["Ana"],
        stats: %{used_bytes: @gb, quota_bytes: @gb},
        backup: {:error, :unreadable}
      )

    assert html =~ ~S(status-line--attention)
    assert html =~ "Disco quase cheio"

    assert html =~ ~S(status-line--problem)
    assert html =~ "Último backup falhou"

    # a caixa segue no ar: o alívio vai junto do aviso
    assert html =~ "Tudo no ar"
    assert html =~ "Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo."
  end

  # load error (componente puro: o contexto não falha sob demanda)
  test "degradado: cartão de erro quando a nuvem não responde", %{conn: _conn} do
    html = render_component(&TainaWeb.SaudeLive.saude_body/1, %{load_error: true, painel: nil})

    assert html =~ "error-card"
    assert html =~ "Não conseguimos falar com a nuvem agora."
    assert html =~ "Tentar de novo"
    refute html =~ "ESTADO DA NUVEM"
  end

  test "morador lê as linhas do presente: backup ainda não houve, verificação desligada", %{
    conn: conn,
    morador: morador
  } do
    {:ok, lv, html} = conn |> log_in(morador) |> live(~p"/saude")

    assert html =~ "ESTADO DA NUVEM"

    # caixa nova: nunca houve backup, e isso é atenção (âmbar), não problema
    assert html =~ "status-line--attention"
    assert html =~ "Nenhum backup ainda"

    # o default soberano: a verificação desligada se diz como estado
    assert html =~ "status-line--unknown"
    assert html =~ "Verificação desligada"

    # com algo em atenção, a saída do morador é falar com quem cuida
    assert html =~ "Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo."

    # sem botão para quem não cuida
    refute has_element?(lv, ~S(button[phx-click="run_backup"]))
  end

  test "zelador com backup configurado ganha o passo 'Fazer backup agora'", %{
    conn: conn,
    tekoa: tekoa,
    zelador: zelador
  } do
    Application.put_env(:taina, :backup, enabled: true, dir: backup_dir())

    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/saude")

    assert html =~ "Nenhum backup ainda"
    assert has_element?(lv, ~S(button[phx-click="run_backup"]))

    lv |> element(~S(button[phx-click="run_backup"])) |> render_click()

    assert render(lv) =~ "Backup a caminho. Volte daqui a pouco para conferir."
    assert {:ok, %{events: events}} = Maraca.list_events(Scope.new(zelador, tekoa))
    event = Enum.find(events, &(&1.tipo == "backup_scheduled"))
    assert %{tipo: "backup_scheduled"} = event
    assert event.tipo == "backup_scheduled"
    assert event.payload["actor"] == zelador.public_id
  end

  test "zelador sem backup configurado ouve isso, sem botão de beco sem saída", %{conn: conn, zelador: zelador} do
    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/saude")

    assert html =~ "Nenhum backup ainda"
    assert html =~ "Você cuida da nuvem. O backup é a sua parte; os arquivos continuam de cada um."
    refute has_element?(lv, ~S(button[phx-click="run_backup"]))
  end

  test "disco acabando é atenção: ícone e palavra junto, nunca alarme", %{conn: conn, tekoa: tekoa, morador: morador} do
    Repo.with_tekoa(tekoa.public_id, fn ->
      {:ok, tekoa |> Changeset.change(storage_used_bytes: tekoa.storage_quota_bytes) |> Repo.update!()}
    end)

    {:ok, _lv, html} = conn |> log_in(morador) |> live(~p"/saude")

    assert html =~ "status-line--attention"
    assert html =~ "Disco quase cheio"
    assert html =~ "Vale falar com quem cuida da nuvem. Ninguém perdeu arquivo."
  end

  test "Saúde renderiza a casca page com o título no cabeçalho (a casca é quem possui o título)", %{
    conn: conn,
    morador: morador
  } do
    {:ok, lv, _html} = conn |> log_in(morador) |> live(~p"/saude")

    assert has_element?(lv, ".page-header__title", "Saúde da comunidade")
  end

  test "unrelated messages leave the live view unchanged", %{conn: conn, morador: morador} do
    {:ok, lv, _html} = conn |> log_in(morador) |> live(~p"/saude")
    html = render(lv)

    send(lv.pid, {:unrelated_pubsub_event, :ignored})

    assert render(lv) == html
  end

  defp saude_body_html(opts) do
    painel =
      %{
        stats: Keyword.get(opts, :stats, %{used_bytes: 0, quota_bytes: @gb}),
        backup: Keyword.fetch!(opts, :backup),
        update_status: Keyword.get(opts, :update_status, %{running: "0.2.0", result: :up_to_date}),
        zelador?: Keyword.fetch!(opts, :zelador?),
        zeladores: Keyword.fetch!(opts, :zeladores)
      }

    render_component(&TainaWeb.SaudeLive.saude_body/1, %{load_error: false, painel: painel})
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp backup_dir do
    dir = Path.join(System.tmp_dir!(), "taina_saude_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
