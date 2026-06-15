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
    test "lista admins primeiro, depois membros por ordem de entrada" do
      tekoa = tekoa_fixture()
      member = confirmed_ava_fixture(tekoa)
      admin = admin_fixture(tekoa)
      scope = Scope.new(admin, tekoa)

      assert {:ok, [first, second]} = Maraca.list_members(scope)
      assert first.id == admin.id
      assert second.id == member.id
    end

    test "inclui convites pendentes (contas não confirmadas)" do
      tekoa = tekoa_fixture()
      admin = admin_fixture(tekoa)
      pending = ava_fixture(tekoa)
      scope = Scope.new(admin, tekoa)

      assert {:ok, members} = Maraca.list_members(scope)
      assert Enum.any?(members, &(&1.id == pending.id and is_nil(&1.confirmed_at)))
    end
  end

  describe "count_members/1" do
    test "conta todas as contas da tekoa" do
      tekoa = tekoa_fixture()
      admin = admin_fixture(tekoa)
      _member = confirmed_ava_fixture(tekoa)
      _pending = ava_fixture(tekoa)

      assert {:ok, 3} = Maraca.count_members(Scope.new(admin, tekoa))
    end
  end
end
