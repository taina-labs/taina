defmodule TainaWeb.TrashLiveTest do
  use TainaWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira

  setup do
    tekoa = tekoa_fixture()
    ava = active_ava_fixture(tekoa)
    scope = Scope.new(ava, tekoa)
    {:ok, file} = Ybira.upload(scope, tmp_upload_fixture("oi", "antiga.txt"))
    {:ok, _} = Ybira.delete_file(scope, file.public_id)
    # `:file` é chave reservada do contexto ExUnit (caminho do arquivo de teste).
    %{scope: scope, ava: ava, trashed_file: file}
  end

  test "lista itens com prazo de purga", %{conn: conn, ava: ava, trashed_file: file} do
    {:ok, _lv, html} = conn |> log_in(ava) |> live(~p"/arquivos/lixeira")

    assert html =~ file.original_filename
    assert html =~ "Apagado hoje"
    assert html =~ "30 dias"
  end

  test "restaura um arquivo", %{conn: conn, scope: scope, ava: ava, trashed_file: file} do
    {:ok, lv, _html} = conn |> log_in(ava) |> live(~p"/arquivos/lixeira")

    lv |> element(~s(button[phx-value-id="#{file.public_id}"])) |> render_click()

    assert render(lv) =~ "Lixeira vazia"
    assert {:ok, restored} = Ybira.get_file(scope, file.public_id)
    assert is_nil(restored.deleted_at)
  end
end
