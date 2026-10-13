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

  describe "revoke_invite/2" do
    test "zelador revoga convite pendente: apaga a linha e registra no mural" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      scope = Scope.new(zelador, tekoa)
      {:ok, %{ava: invited}} = Maraca.invite_user(zelador, tekoa)

      assert {:ok, _revoked} = Maraca.revoke_invite(scope, invited.public_id)

      assert {:ok, members} = Maraca.list_members(scope)
      refute Enum.any?(members, &(&1.public_id == invited.public_id))

      assert {:ok, %{events: events}} = Maraca.list_events(scope)
      assert Enum.any?(events, &(&1.tipo == "invite_revoked"))
    end

    test "morador comum não revoga" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)
      {:ok, %{ava: invited}} = Maraca.invite_user(zelador, tekoa)

      assert {:error, :unauthorized} =
               Maraca.revoke_invite(Scope.new(morador, tekoa), invited.public_id)
    end

    test "não revoga conta já ativada" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)

      assert {:error, :not_pending} =
               Maraca.revoke_invite(Scope.new(zelador, tekoa), morador.public_id)
    end

    test "convite pendente de zelador não conta como zelador ativo" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      scope = Scope.new(zelador, tekoa)
      # O convite pendente não é gente ainda: não pode impedir a proteção do
      # último zelador de verdade.
      {:ok, %{ava: _invited}} = Maraca.invite_user(zelador, tekoa, role: :zelador)

      assert {:error, :last_zelador} = Maraca.deactivate_member(scope, zelador.public_id)
    end
  end

  describe "invite_expired?/1" do
    test "convite recém-criado não está expirado" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      {:ok, %{ava: invited}} = Maraca.invite_user(zelador, tekoa)

      refute Maraca.invite_expired?(invited)
    end
  end
end
