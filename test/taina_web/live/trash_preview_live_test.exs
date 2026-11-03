defmodule TainaWeb.TrashPreviewLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    owner = active_ava_fixture(tekoa)
    {:ok, file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture("lixeira", "apagado.txt"))
    {:ok, _} = Ybira.delete_file(Scope.new(owner, tekoa), file.rkey)
    %{tekoa: tekoa, owner: owner, trashed_file: file}
  end

  test "owner can preview and restore a trashed file", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    trashed_file: file
  } do
    {:ok, lv, html} = conn |> log_in(owner) |> live(~p"/documentos/lixeira/#{file.rkey}")

    assert html =~ file.nome
    assert html =~ "Este arquivo está na lixeira."
    assert has_element?(lv, "#trash-file-actions .actions-menu__trigger")
    assert has_element?(lv, "#trash-file-actions-panel", "Baixar")
    assert has_element?(lv, "#trash-file-actions-panel", "Restaurar")
    assert has_element?(lv, "#trash-file-actions-panel", "Apagar definitivamente")
    refute has_element?(lv, ".page-header__zone--end > button", "Baixar")
    refute has_element?(lv, ".page-header__zone--end > button", "Restaurar")

    assert {:error, {:live_redirect, %{to: "/documentos/lixeira"}}} =
             lv |> element("#trash-file-actions-panel button", "Restaurar") |> render_click()

    assert {:ok, restored} = Ybira.get_file(Scope.new(owner, tekoa), file.rkey)
    assert is_nil(restored.apagado_em)
  end

  test "another resident cannot resolve an owner's trashed file", %{
    tekoa: tekoa,
    trashed_file: file
  } do
    other = active_ava_fixture(tekoa, %{username: "outra"})

    assert {:error, :not_found} = Ybira.get_trashed_file(Scope.new(other, tekoa), file.rkey)
  end

  test "permanently purges from the trash file preview after confirmation", %{
    conn: conn,
    tekoa: tekoa,
    owner: owner,
    trashed_file: file
  } do
    {:ok, lv, _html} = conn |> log_in(owner) |> live(~p"/documentos/lixeira/#{file.rkey}")

    lv |> element("#trash-file-actions-panel button", "Apagar definitivamente") |> render_click()
    assert has_element?(lv, "#confirm-trash-purge .dialog__title", "Apagar apagado.txt de vez?")

    assert {:error, {:live_redirect, %{to: "/documentos/lixeira"}}} =
             lv |> element("#confirm-trash-purge button[phx-click=\"confirm-purge\"]") |> render_click()

    assert {:error, :not_found} = Ybira.get_trashed_file(Scope.new(owner, tekoa), file.rkey)
  end
end
