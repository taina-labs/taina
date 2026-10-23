defmodule Ypy.Maraca.PolicyTest do
  use ExUnit.Case, async: true

  alias Ypy.Maraca.Policy

  describe "the read rule (praca OR dono OR concessao)" do
    test "nobody asks to read the praca" do
      for leitor <- [1, 2, 99] do
        assert Policy.can_read?(:praca, leitor, 7, "rkey-1", [])
      end
    end

    test "the dono reads the dono's casa" do
      assert Policy.can_read?(:casa, 7, 7, "rkey-1", [])
    end

    test "another morador does not read a casa without a concessao" do
      refute Policy.can_read?(:casa, 2, 7, "rkey-1", [])
    end

    test "a concessao for this leitor on this recurso opens the casa" do
      concessoes = [%{leitor_id: 2, recurso: "rkey-1"}]

      assert Policy.can_read?(:casa, 2, 7, "rkey-1", concessoes)
    end

    test "a concessao for another leitor or another recurso does not" do
      concessoes = [%{leitor_id: 3, recurso: "rkey-1"}, %{leitor_id: 2, recurso: "rkey-2"}]

      refute Policy.can_read?(:casa, 2, 7, "rkey-1", concessoes)
    end

    test "the zelador has no shortcut" do
      refute Policy.can_read?(:casa, 1, 7, "rkey-1", [])

      concessoes = [%{leitor_id: 1, recurso: "rkey-1"}]

      assert Policy.can_read?(:casa, 1, 7, "rkey-1", concessoes)
    end

    test "a zona that is not one of the two reads as closed" do
      refute Policy.can_read?(:local, 7, 7, "rkey-1", [])
    end
  end

  describe "papeis" do
    test "zelador is the machine care role" do
      assert Policy.zelador?(:zelador)
      refute Policy.zelador?(:morador)
    end

    test "morador is the plain member role" do
      assert Policy.morador?(:morador)
      refute Policy.morador?(:zelador)
    end

    test "zonas and papeis are the two fixed lists" do
      assert Policy.zonas() == [:casa, :praca]
      assert Policy.papeis() == [:zelador, :morador]
    end
  end

  describe "invite and reset expiry" do
    test "nil sent_at is already expired" do
      agora = DateTime.utc_now()

      assert Policy.invite_expired?(nil, agora)
      assert Policy.reset_expired?(nil, agora)
    end

    test "an invite lasts 2 days" do
      emitido = DateTime.from_naive!(~N[2026-06-01 10:00:00], "Etc/UTC")

      refute Policy.invite_expired?(
               emitido,
               DateTime.shift(emitido, second: 2 * 24 * 60 * 60 - 1)
             )

      refute Policy.invite_expired?(emitido, DateTime.shift(emitido, day: 2))

      assert Policy.invite_expired?(
               emitido,
               DateTime.shift(emitido, second: 2 * 24 * 60 * 60 + 1)
             )
    end

    test "a reset link lasts 30 minutes" do
      emitido = DateTime.from_naive!(~N[2026-06-01 10:00:00], "Etc/UTC")

      refute Policy.reset_expired?(emitido, DateTime.shift(emitido, second: 30 * 60 - 1))
      refute Policy.reset_expired?(emitido, DateTime.shift(emitido, minute: 30))
      assert Policy.reset_expired?(emitido, DateTime.shift(emitido, second: 30 * 60 + 1))
    end

    test "the generic predicate takes the bound" do
      emitido = DateTime.from_naive!(~N[2026-06-01 10:00:00], "Etc/UTC")

      refute Policy.expired?(emitido, DateTime.shift(emitido, second: 59), 60)
      assert Policy.expired?(emitido, DateTime.shift(emitido, second: 61), 60)
    end
  end
end
