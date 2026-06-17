defmodule Taina.MaracaMembersTest do
  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope

  describe "bootstrapped?/0 e get_tekoa/0" do
    test "instância virgem não está bootstrapped" do
      refute Maraca.bootstrapped?()
      assert {:error, :not_bootstrapped} = Maraca.get_tekoa()
    end

    test "com Tekoa criada, devolve a Tekoa única" do
      tekoa = tekoa_fixture()

      assert Maraca.bootstrapped?()
      assert {:ok, found} = Maraca.get_tekoa()
      assert found.id == tekoa.id
    end
  end

  describe "list_members/1" do
    test "lista zeladores primeiro, depois moradores por ordem de entrada" do
      tekoa = tekoa_fixture()
      morador = active_ava_fixture(tekoa)
      zelador = zelador_fixture(tekoa)
      scope = Scope.new(zelador, tekoa)

      assert {:ok, [first, second]} = Maraca.list_members(scope)
      assert first.id == zelador.id
      assert second.id == morador.id
    end

    test "inclui convites pendentes (sem nome ainda)" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      pending = ava_fixture(tekoa)
      scope = Scope.new(zelador, tekoa)

      assert {:ok, members} = Maraca.list_members(scope)
      assert Enum.any?(members, &(&1.id == pending.id and is_nil(&1.activated_at)))
    end
  end

  describe "count_members/1" do
    test "conta todas as contas da tekoa" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      _morador = active_ava_fixture(tekoa)
      _pending = ava_fixture(tekoa)

      assert {:ok, 3} = Maraca.count_members(Scope.new(zelador, tekoa))
    end
  end
end
