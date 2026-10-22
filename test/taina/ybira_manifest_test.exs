defmodule Taina.Ybira.ManifestTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Scope
  alias Taina.Ybira
  alias Taina.Ybira.Manifest

  setup do
    tekoa = tekoa_fixture()
    dono = active_ava_fixture(tekoa)
    %{scope: Scope.new(dono, tekoa), tekoa: tekoa, dono: dono}
  end

  test "todo arquivo legivel, do mais antigo para o mais novo", %{scope: scope} do
    {:ok, primeira} = Ybira.upload(scope, tmp_upload_fixture("1", "a.txt"))
    {:ok, segunda} = Ybira.upload(scope, tmp_upload_fixture("2", "b.txt"))
    {:ok, terceira} = Ybira.upload(scope, tmp_upload_fixture("3", "c.txt"))

    {:ok, %{items: items, next_cursor: next}} = Manifest.page(scope)

    assert next == nil
    assert Enum.map(items, & &1.rkey) == [primeira.rkey, segunda.rkey, terceira.rkey]
  end

  test "limit com cursor rkey: a pagina seguinte vem depois do ultimo", %{scope: scope} do
    {:ok, primeira} = Ybira.upload(scope, tmp_upload_fixture("1", "a.txt"))
    {:ok, segunda} = Ybira.upload(scope, tmp_upload_fixture("2", "b.txt"))
    {:ok, terceira} = Ybira.upload(scope, tmp_upload_fixture("3", "c.txt"))

    {:ok, %{items: items, next_cursor: next}} = Manifest.page(scope, limit: 2)
    assert Enum.map(items, & &1.rkey) == [primeira.rkey, segunda.rkey]
    assert is_binary(next)

    {:ok, %{items: restantes, next_cursor: fim}} = Manifest.page(scope, limit: 2, after: next)
    assert Enum.map(restantes, & &1.rkey) == [terceira.rkey]
    assert fim == nil
  end

  test "o que esta na lixeira nao volta no manifesto", %{scope: scope} do
    {:ok, fica} = Ybira.upload(scope, tmp_upload_fixture("1", "a.txt"))
    {:ok, some} = Ybira.upload(scope, tmp_upload_fixture("2", "b.txt"))
    {:ok, _} = Ybira.delete_file(scope, some.rkey)

    {:ok, %{items: items}} = Manifest.page(scope)

    assert Enum.map(items, & &1.rkey) == [fica.rkey]
  end

  test "casa alheia so entra com concessao", %{tekoa: tekoa, dono: dono} do
    outro = active_ava_fixture(tekoa)
    scope_outro = Scope.new(outro, tekoa)

    {:ok, secreta} = Ybira.upload(scope_outro, tmp_upload_fixture("segredo", "casa.txt"))

    {:ok, %{items: items}} = Manifest.page(Scope.new(dono, tekoa))
    assert items == []

    {:ok, _} = Taina.Maraca.conceder(Scope.new(outro, tekoa), "ypy.file.v0", secreta.rkey, dono)

    {:ok, %{items: items}} = Manifest.page(Scope.new(dono, tekoa))
    assert Enum.map(items, & &1.rkey) == [secreta.rkey]
  end
end
