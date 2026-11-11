defmodule TainaWeb.TrashLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    scope = Scope.new(ava, tekoa)
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "antiga.txt"))
    {:ok, _} = Ybira.delete_file(scope, file.rkey)
    # `:file` é chave reservada do contexto ExUnit (caminho do arquivo de teste).
    %{scope: scope, ava: ava, trashed_file: file}
  end

  # --- board "Lixeira / padrao" (M e Web) ---

  test "lista itens com a cópia de ensino, o prazo e as ações da lixeira", %{
    conn: conn,
    ava: ava,
    trashed_file: file
  } do
    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    assert html =~ file.nome
    assert html =~ "Os itens ficam 30 dias na lixeira e depois são apagados de vez."
    assert html =~ "restam 30 dias"
    assert has_element?(lv, "#trash-file-#{file.rkey}-trigger")
    assert has_element?(lv, "#trash-file-#{file.rkey}-panel", "Restaurar")
    assert has_element?(lv, "#trash-file-#{file.rkey}-panel", "Apagar definitivamente")
    assert has_element?(lv, ~s(a[href="/documentos/lixeira/#{file.rkey}"]), file.nome)
    # quadradinho da lixeira em todas as linhas
    assert has_element?(lv, ".service-square--lixeira")
    assert has_element?(lv, ~S(.service-tab-bar__item[aria-current="page"]), "Lixeira")
  end

  test "quando a janela fecha, o prazo avisa antes de apagar", %{
    conn: conn,
    scope: scope,
    ava: ava,
    trashed_file: file
  } do
    {:ok, %{items: items}} = Ybira.list_trash(scope)
    na_lixeira = Enum.find(items, &(&1.rkey == file.rkey))

    apagado_ha_26_dias =
      DateTime.utc_now() |> DateTime.shift(day: -26) |> DateTime.truncate(:second)

    na_lixeira |> Ecto.Changeset.change(apagado_em: apagado_ha_26_dias) |> Repo.update!()

    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    assert html =~ "restam 4 dias, apaga em breve"
    assert has_element?(lv, ".list-row__meta.text-warning", "apaga em breve")
  end

  # --- board "Lixeira / vazio" ---

  test "lixeira vazia mostra o estado do board", %{conn: conn, scope: scope, ava: ava} do
    {:ok, %{items: [na_lixeira]}} = Ybira.list_trash(scope)
    {:ok, _} = Ybira.restore_file(scope, na_lixeira.rkey)

    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    assert html =~ "A lixeira está vazia"
    assert html =~ "Nada foi apagado. O que você apagar aparece aqui por 30 dias antes de sumir de vez."
  end

  # --- fluxos preservados ---

  test "restaura um arquivo", %{conn: conn, scope: scope, ava: ava, trashed_file: file} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    lv |> element("#trash-file-#{file.rkey}-panel button", "Restaurar") |> render_click()

    assert render(lv) =~ "A lixeira está vazia"
    assert {:ok, restored} = Ybira.get_file(scope, file.rkey)
    assert is_nil(restored.apagado_em)
  end

  test "permanent deletion requires confirmation and reclaims the item", %{
    conn: conn,
    scope: scope,
    ava: ava,
    trashed_file: file
  } do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    lv |> element("#trash-file-#{file.rkey}-panel button", "Apagar definitivamente") |> render_click()

    assert has_element?(lv, "#confirm-purge .dialog__title", "Apagar antiga.txt de vez?")
    assert has_element?(lv, "#confirm-purge .dialog__body", "Este arquivo não poderá ser restaurado.")

    lv |> element("#confirm-purge button[phx-click=\"confirm_purge\"]") |> render_click()

    assert render(lv) =~ "A lixeira está vazia"
    assert {:error, :not_found} = Ybira.get_file(scope, file.rkey)
  end

  test "restores multiple selected files", %{conn: conn, scope: scope, ava: ava, trashed_file: first} do
    {:ok, second} = Ybira.upload(scope, tmp_upload_fixture("segundo", "segundo.txt"))
    {:ok, _} = Ybira.delete_file(scope, second.rkey)
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    lv |> element(~s(input[phx-value-type="file"][phx-value-id="#{first.rkey}"])) |> render_click()
    lv |> element(~s(input[phx-value-type="file"][phx-value-id="#{second.rkey}"])) |> render_click()

    assert has_element?(lv, "#trash-selection-toolbar", "2 itens selecionados")

    lv |> element("button[phx-click=restore_selected]") |> render_click()

    assert render(lv) =~ "2 itens restaurados."
    assert {:ok, _} = Ybira.get_file(scope, first.rkey)
    assert {:ok, _} = Ybira.get_file(scope, second.rkey)
  end

  test "permanently deletes multiple selected files after confirmation", %{
    conn: conn,
    scope: scope,
    ava: ava,
    trashed_file: first
  } do
    {:ok, second} = Ybira.upload(scope, tmp_upload_fixture("segundo", "segundo.txt"))
    {:ok, _} = Ybira.delete_file(scope, second.rkey)
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    lv |> element(~s(input[phx-value-type="file"][phx-value-id="#{first.rkey}"])) |> render_click()
    lv |> element(~s(input[phx-value-type="file"][phx-value-id="#{second.rkey}"])) |> render_click()
    lv |> element("button[phx-click=ask_purge_selected]") |> render_click()

    assert has_element?(lv, "#confirm-purge .dialog__title", "Apagar 2 itens de vez?")

    lv |> element("#confirm-purge button[phx-click=\"confirm_purge\"]") |> render_click()

    assert render(lv) =~ "A lixeira está vazia"
    assert {:error, :not_found} = Ybira.get_trashed_file(scope, first.rkey)
    assert {:error, :not_found} = Ybira.get_trashed_file(scope, second.rkey)
  end

  test "selecting a deleted folder and its contents restores the subtree once", %{
    conn: conn,
    scope: scope,
    ava: ava
  } do
    {:ok, root} = Ybira.create_folder(scope, %{name: "Raiz"})
    {:ok, child} = Ybira.create_folder(scope, %{name: "Filha", parent_rkey: root.rkey})
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("dentro", "dentro.txt"), folder_rkey: child.rkey)
    {:ok, :deleted} = Ybira.delete_folder(scope, root.rkey)
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    lv |> element(~s(input[phx-value-type="folder"][phx-value-id="#{root.rkey}"])) |> render_click()
    lv |> element(~s(input[phx-value-type="folder"][phx-value-id="#{child.rkey}"])) |> render_click()
    lv |> element(~s(input[phx-value-type="file"][phx-value-id="#{file.rkey}"])) |> render_click()

    lv |> element("button[phx-click=restore_selected]") |> render_click()

    assert render(lv) =~ "1 item restaurado."
    assert {:ok, restored_root} = Ybira.get_folder(scope, root.rkey)
    assert {:ok, restored_child} = Ybira.get_folder(scope, child.rkey)
    assert {:ok, restored_file} = Ybira.get_file(scope, file.rkey)
    assert restored_child.parent_id == restored_root.id
    assert restored_file.folder_id == restored_child.id
  end

  test "restaura uma pasta junto com o que tem dentro", %{conn: conn, scope: scope, ava: ava} do
    {:ok, folder} = Ybira.create_folder(scope, %{name: "ferias"})
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("x", "foto.txt"), folder_rkey: folder.rkey)
    {:ok, :deleted} = Ybira.delete_folder(scope, folder.rkey)

    {:ok, lv, html} = conn |> log_in(ava) |> live(~p"/documentos/lixeira")

    assert html =~ "ferias"
    assert html =~ "restam 30 dias"

    lv |> element("#trash-folder-#{folder.rkey}-panel button", "Restaurar") |> render_click()

    assert render(lv) =~ "Pasta restaurada com o que tinha dentro."
    assert {:ok, restored_folder} = Ybira.get_folder(scope, folder.rkey)
    assert {:ok, restored_file} = Ybira.get_file(scope, file.rkey)
    # O arquivo volta dentro da pasta, não solto na raiz.
    assert restored_file.folder_id == restored_folder.id
  end
end
