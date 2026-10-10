defmodule TainaWeb.SaudeLiveTest do
  @moduledoc """
  Tela "Saúde da comunidade" (RFC_003 seção 6, camada 2): fatos do presente em
  frases simples. Morador lê tudo; quem cuida da máquina ganha o próximo passo
  do backup quando ele existe. Mutando config de backup, roda sem async.
  """

  use TainaWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Ecto.Changeset
  alias Taina.Nhaman.Backup
  alias Taina.Repo

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

  test "morador lê os fatos: disco, moradores, atualização e a caixa", %{
    conn: conn,
    tekoa: tekoa,
    morador: morador
  } do
    {:ok, _lv, html} = conn |> log_in(morador) |> live(~p"/saude")

    assert html =~ "Saúde da comunidade"

    # Disco em unidades humanas, nunca bytes crus.
    assert html =~ "0 B usados de 1,0 GB. 1,0 GB livres."

    # Moradores e quem cuida da máquina.
    assert html =~ "2 moradores"
    assert html =~ "Quem cuida da máquina: Ana."

    # Atualização desligada (o default soberano): dita como estado, sem
    # fingir "atualizado".
    assert html =~ "A verificação de atualizações está desligada"
    assert html =~ "não conversa com a internet por conta própria"
    assert html =~ "A caixa está na versão 0.1.0."

    # A caixa: nome da Tekoa e o endereço que a comunidade usa.
    assert html =~ "Esta é a caixa de #{tekoa.name}."
    assert html =~ "Vocês acessam por localhost."

    # Sem backup ainda: cuidado, não recusa, sem botão para morador.
    assert html =~ "Nenhum backup ainda."
    assert html =~ "Quem cuida da máquina cuida do backup."
    refute html =~ "Fazer backup agora"

    # Jobs zerados não mostram linha ("0" não é fato).
    refute html =~ "Trabalhos da caixa"
  end

  test "zelador com backup configurado ganha o passo 'Fazer backup agora'", %{conn: conn, zelador: zelador} do
    Application.put_env(:taina, :backup, enabled: true, dir: backup_dir())

    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/saude")

    assert html =~ "Nenhum backup ainda."
    assert html =~ "Quem cuida da máquina pode fazer um agora."
    assert has_element?(lv, ~s(button[phx-click="run-backup"]))
  end

  test "zelador sem backup configurado ouve isso, sem botão de beco sem saída", %{conn: conn, zelador: zelador} do
    {:ok, lv, html} = conn |> log_in(zelador) |> live(~p"/saude")

    assert html =~ "Nenhum backup ainda."
    assert html =~ "Quem cuida da máquina ainda não configurou onde guardar os backups."
    refute has_element?(lv, ~s(button[phx-click="run-backup"]))
  end

  test "último backup lido do destino: quando terminou bem e quanto guardou", %{conn: conn, zelador: zelador} do
    dir = backup_dir()

    at = DateTime.utc_now() |> DateTime.shift(day: -2) |> DateTime.truncate(:second)
    File.write!(Path.join(dir, Backup.archive_filename(at)), "bytes do cofre")
    Application.put_env(:taina, :backup, enabled: true, dir: dir)

    {:ok, _lv, html} = conn |> log_in(zelador) |> live(~p"/saude")

    assert html =~ "Terminou bem há 2 dias (14 B guardados)."
  end

  test "disco acabando é aviso ambiente: ícone e frase junto, nunca alarme", %{conn: conn, tekoa: tekoa, morador: morador} do
    Repo.with_tekoa(tekoa.public_id, fn ->
      {:ok, tekoa |> Changeset.change(storage_used_bytes: tekoa.storage_quota_bytes) |> Repo.update!()}
    end)

    {:ok, _lv, html} = conn |> log_in(morador) |> live(~p"/saude")

    assert html =~ "1,0 GB usados de 1,0 GB. 0 B livres."
    assert html =~ "O espaço está acabando."
  end

  test "Saúde aparece na navegação de baixo e na lateral", %{conn: conn, morador: morador} do
    {:ok, lv, _html} = conn |> log_in(morador) |> live(~p"/saude")

    assert has_element?(lv, ".bottom-nav a[href='/saude']")
    assert has_element?(lv, ".sidebar__nav a[href='/saude']")
  end

  defp backup_dir do
    dir = Path.join(System.tmp_dir!(), "taina_saude_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
