defmodule Taina.MuralTest do
  @moduledoc """
  O mural e a projecao da cadeia unica (RFC_006, secao 8): toda entrada e um
  fato assinado, o ato do produto ou o verbo do kernel.

  Cobre o contrato do registro: gravar sem nunca derrubar o ato, ler em ordem
  com paginação, e os caminhos do dia a dia (convite, zonas, concessao,
  papel) deixando cada ato na cadeia.
  """

  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Scope
  alias Taina.Ybira
  alias Ypy.Mural.Entry

  describe "record_event/3 (atos do produto)" do
    setup do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa, %{display_name: "Ana"})

      %{tekoa: tekoa, zelador: zelador, scope: Scope.new(zelador, tekoa)}
    end

    test "grava o ato com o ator no payload e a entrada assinada", %{scope: scope} do
      assert :ok = Maraca.record_event(scope, :invite_created, %{"role" => "morador"})

      assert {:ok, %{events: [%Entry{} = entry]}} = Maraca.list_events(scope)

      assert entry.tipo == "invite_created"
      assert entry.payload["actor"] == scope.ava.public_id
      assert entry.payload["role"] == "morador"
      assert entry.signature
      assert entry.inserted_at
      # Ledger append-only: a entrada da cadeia nao tem updated_at.
      refute Map.has_key?(%Entry{}, :updated_at)
    end

    test "falha na escrita do ledger devolve :ok, nunca derruba o chamador", %{scope: scope} do
      # Tekoa que nao existe no banco: o insert da entrada viola a FK, logado
      # e engolido.
      fantasma = Scope.new(scope.ava, %Ypy.Maraca.Tekoa{public_id: "tekoa_nunca_vista"})

      assert :ok = Maraca.record_event(fantasma, :invite_created, %{})

      assert {:ok, %{events: []}} = Maraca.list_events(scope)
    end

    # Camada 3 da transparência (RFC_003 seção 6): o substrato de telemetria
    # sobe com a app (métrica `taina.maraca.event.count`), a caixa é soberana,
    # nada sai dela. O teste se prende ao evento direto do `:telemetry`.
    test "evento gravado emite telemetria com o tipo, sem ids de tekoa/ava", %{scope: scope} do
      handler_id = "mural-telemetry-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:taina, :maraca, :event],
          fn event, measurements, metadata, _config -> send(self(), {event, measurements, metadata}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = Maraca.record_event(scope, :invite_created, %{"role" => "morador"})

      assert_received {[:taina, :maraca, :event], %{count: 1}, %{type: :invite_created}}
    end
  end

  describe "list_events/2 (a projecao da cadeia)" do
    setup do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa, %{display_name: "Ana"})

      %{tekoa: tekoa, ava: ava, scope: Scope.new(ava, tekoa)}
    end

    test "mais novas primeiro, pela ordem da cadeia", %{scope: scope} do
      for i <- 1..3, do: :ok = Maraca.record_event(scope, :quota_changed, %{"to" => i})

      assert {:ok, %{events: events}} = Maraca.list_events(scope)
      assert length(events) == 3
      # A ordem da cadeia: sequência crescente, projecao decrescente.
      assert Enum.map(events, & &1.seq) == [3, 2, 1]
      assert Enum.map(events, & &1.payload["to"]) == [3, 2, 1]
    end

    test "pagina por offset e sinaliza a próxima página", %{scope: scope} do
      for i <- 1..3, do: :ok = Maraca.record_event(scope, :quota_changed, %{"to" => i})

      assert {:ok, %{events: page1, next_offset: 2}} = Maraca.list_events(scope, limit: 2)
      assert Enum.map(page1, & &1.payload["to"]) == [3, 2]

      assert {:ok, %{events: page2, next_offset: nil}} = Maraca.list_events(scope, limit: 2, offset: 2)
      assert Enum.map(page2, & &1.payload["to"]) == [1]
    end
  end

  describe "atos do dia a dia deixam entrada na cadeia" do
    setup do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa, %{display_name: "Ana"})
      morador = active_ava_fixture(tekoa, %{display_name: "Bruno"})

      %{tekoa: tekoa, zelador: zelador, morador: morador, scope: Scope.new(zelador, tekoa)}
    end

    test "convite e aceite registram quem convidou e quem entrou", %{tekoa: tekoa, zelador: zelador, scope: scope} do
      assert {:ok, %{token: token}} = Maraca.invite_user(zelador, tekoa)

      assert {:ok, _accepted} =
               Maraca.accept_invite(token, %{
                 "username" => "maria",
                 "display_name" => "Maria",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })

      assert {:ok, %{events: events}} = Maraca.list_events(scope)
      tipos = Enum.map(events, & &1.tipo)
      assert "invite_accepted" in tipos
      assert "invite_created" in tipos
    end

    test "publicar e tirar da praca ficam na cadeia (verbos do kernel)", %{scope: scope} do
      path = tmp_upload_fixture("conteudo", "estatuto.pdf")
      assert {:ok, file} = Ybira.upload(scope, path, filename: "estatuto.pdf")

      assert {:ok, _file} = Ybira.publicar_file(scope, file.rkey)
      assert {:ok, _file} = Ybira.tirar_file_da_praca(scope, file.rkey)

      assert {:ok, %{events: events}} = Maraca.list_events(scope)
      tipos = Enum.map(events, & &1.tipo)
      assert "publicar" in tipos
      assert "tirar_da_praca" in tipos

      publicar = Enum.find(events, &(&1.tipo == "publicar"))
      assert publicar.payload["rkey"] == file.rkey
    end

    test "pedido aprovado nasce como concessao na cadeia", %{
      tekoa: tekoa,
      morador: morador,
      scope: scope
    } do
      path = tmp_upload_fixture("segredo", "diario.txt")
      assert {:ok, file} = Ybira.upload(scope, path, filename: "diario.txt")

      morador_scope = Scope.new(morador, tekoa)
      assert {:ok, pedido} = Maraca.pedir_acesso(morador_scope, "ypy.file.v0", file.rkey, "quero ler")

      assert {:ok, _concessao} = Maraca.aprovar(scope, pedido)

      assert {:ok, %{events: events}} = Maraca.list_events(scope)
      assert "concessao" in Enum.map(events, & &1.tipo)
    end

    test "mudança de papel fica na cadeia (verbo do kernel)", %{morador: morador, scope: scope} do
      assert {:ok, _member} = Maraca.update_member_role(scope, morador.public_id, :zelador)

      assert {:ok, %{events: [event]}} = Maraca.list_events(scope)
      assert event.tipo == "mudar_papel"
      assert event.payload["papel"] == "zelador"
    end

    test "atos só do produto registram com o ator", %{morador: morador, scope: scope} do
      assert {:ok, _member} = Maraca.deactivate_member(scope, morador.public_id)

      assert {:ok, %{events: [event]}} = Maraca.list_events(scope)
      assert event.tipo == "member_deactivated"
      assert event.payload["actor"] == scope.ava.public_id
    end

    test "mudança de cota registra de quanto para quanto", %{scope: scope} do
      assert {:ok, _tekoa} = Maraca.update_tekoa_quota(scope, 5 * 1024 ** 3)

      assert {:ok, %{events: [event]}} = Maraca.list_events(scope)
      assert event.tipo == "quota_changed"
      assert event.payload["to"] == 5 * 1024 ** 3
    end
  end
end
