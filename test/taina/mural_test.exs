defmodule Taina.MuralTest do
  @moduledoc """
  Mural (RFC_003 seção 6, camada 1): o registro append-only do "quem fez o quê".

  Cobre o contrato do ledger: gravar sem nunca derrubar o ato, ler em ordem
  com paginação, e os caminhos do dia a dia (convite, zonas, pedidos de
  acesso, cota) registrando cada ato que já executam.
  """

  use Taina.DataCase, async: true

  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Maraca.Event
  alias Taina.Scope
  alias Taina.Ybira

  describe "record_event/4" do
    setup do
      tekoa = tekoa_fixture()
      %{tekoa: tekoa, zelador: zelador_fixture(tekoa, %{display_name: "Ana"})}
    end

    test "grava o ato com autor, payload e public_id", %{tekoa: tekoa, zelador: zelador} do
      assert :ok = Maraca.record_event(tekoa.public_id, zelador.id, :invite_created, %{"role" => "morador"})

      assert {:ok, %{events: [%Event{} = event]}} = Maraca.list_events(Scope.new(zelador, tekoa))

      assert event.type == :invite_created
      assert event.ava_id == zelador.id
      assert event.payload == %{"role" => "morador"}
      assert event.public_id
      assert event.inserted_at
      # Ledger append-only: a linha do mural não tem updated_at.
      refute Map.has_key?(%Event{}, :updated_at)
    end

    test "ato do sistema (sem autor morador) entra com ava_id nil", %{tekoa: tekoa} do
      assert :ok = Maraca.record_event(tekoa.public_id, nil, :quota_changed, %{"to" => 1})

      assert {:ok, %{events: [%Event{ava_id: nil}]}} = Maraca.list_events(Scope.new(ava_fixture(tekoa), tekoa))
    end

    test "falha na escrita do ledger devolve :ok, nunca derruba o chamador", %{tekoa: tekoa} do
      # Tipo fora do vocabulário: changeset inválido, logado e engolido.
      assert :ok = Maraca.record_event(tekoa.public_id, nil, :ato_fora_do_vocabulario, %{})

      assert {:ok, %{events: []}} = Maraca.list_events(Scope.new(ava_fixture(tekoa), tekoa))
    end

    test "tekoa desconhecida: devolve :ok sem registrar nada", %{tekoa: tekoa, zelador: zelador} do
      assert :ok = Maraca.record_event("tekoa_nunca_vista", nil, :invite_created, %{})

      assert {:ok, %{events: []}} = Maraca.list_events(Scope.new(zelador, tekoa))
    end

    # Camada 3 da transparência (RFC_003 seção 6): o substrato de telemetria
    # sobe com a app (métrica `taina.maraca.event.count`), a caixa é soberana,
    # nada sai dela. O teste se prende ao evento direto do `:telemetry`.
    test "evento gravado emite telemetria com o tipo, sem ids de tekoa/ava", %{tekoa: tekoa, zelador: zelador} do
      handler_id = "mural-telemetry-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach(
          handler_id,
          [:taina, :maraca, :event],
          fn event, measurements, metadata, _config -> send(self(), {event, measurements, metadata}) end,
          nil
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      assert :ok = Maraca.record_event(tekoa.public_id, zelador.id, :invite_created, %{"role" => "morador"})

      assert_received {[:taina, :maraca, :event], %{count: 1}, %{type: :invite_created}}
    end
  end

  describe "list_events/2" do
    setup do
      tekoa = tekoa_fixture()
      %{tekoa: tekoa, ava: active_ava_fixture(tekoa, %{display_name: "Ana"})}
    end

    test "mais novos primeiro, com o autor pré-carregado", %{tekoa: tekoa, ava: ava} do
      for i <- 1..3, do: :ok = Maraca.record_event(tekoa.public_id, ava.id, :quota_changed, %{"to" => i})

      assert {:ok, %{events: events}} = Maraca.list_events(Scope.new(ava, tekoa))
      assert length(events) == 3
      # Mesma data, desempate pelo id: mais recente primeiro.
      assert Enum.map(events, & &1.payload["to"]) == [3, 2, 1]
      assert Enum.all?(events, &(&1.ava.display_name == "Ana"))
    end

    test "pagina por offset e sinaliza a próxima página", %{tekoa: tekoa, ava: ava} do
      for i <- 1..3, do: :ok = Maraca.record_event(tekoa.public_id, ava.id, :quota_changed, %{"to" => i})
      scope = Scope.new(ava, tekoa)

      assert {:ok, %{events: page1, next_offset: 2}} = Maraca.list_events(scope, limit: 2)
      assert Enum.map(page1, & &1.payload["to"]) == [3, 2]

      assert {:ok, %{events: page2, next_offset: nil}} = Maraca.list_events(scope, limit: 2, offset: 2)
      assert Enum.map(page2, & &1.payload["to"]) == [1]
    end
  end

  describe "atos do dia a dia registram no mural" do
    setup do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa, %{display_name: "Ana"})
      morador = active_ava_fixture(tekoa, %{display_name: "Bruno"})
      %{tekoa: tekoa, zelador: zelador, morador: morador}
    end

    test "convite e aceite registram quem convidou e quem entrou", %{tekoa: tekoa, zelador: zelador} do
      assert {:ok, invited} = Maraca.invite_user(zelador, tekoa)

      assert {:ok, _accepted} =
               Maraca.accept_invite(invited.invite_token, %{
                 "username" => "maria",
                 "display_name" => "Maria",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })

      assert {:ok, %{events: events}} = Maraca.list_events(Scope.new(zelador, tekoa))
      types = Enum.map(events, & &1.type)
      assert :invite_accepted in types
      assert :invite_created in types
    end

    test "aceite de convite de zelador registra o papel", %{tekoa: tekoa, zelador: zelador} do
      assert {:ok, invited} = Maraca.invite_user(zelador, tekoa, role: :zelador)

      assert {:ok, _accepted} =
               Maraca.accept_invite(invited.invite_token, %{
                 "username" => "joana",
                 "display_name" => "Joana",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })

      assert {:ok, %{events: events}} = Maraca.list_events(Scope.new(zelador, tekoa))
      accepted = Enum.find(events, &(&1.type == :invite_accepted))
      assert accepted.payload["role"] == "zelador"
    end

    test "link de nova senha registra o membro para quem foi gerado", %{
      tekoa: tekoa,
      zelador: zelador,
      morador: morador
    } do
      scope = Scope.new(zelador, tekoa)

      assert {:ok, _ava} = Maraca.mint_reset_link(scope, morador)

      assert {:ok, %{events: [event]}} = Maraca.list_events(scope)
      assert event.type == :reset_link_created
      assert event.payload["member"] == "Bruno"
    end

    test "zonas casa/praca registram publicação e retirada com o nome", %{tekoa: tekoa, zelador: zelador} do
      scope = Scope.new(zelador, tekoa)
      path = tmp_upload_fixture("conteúdo", "estatuto.pdf")
      assert {:ok, file} = Ybira.upload(scope, path, filename: "estatuto.pdf")

      assert {:ok, _file} = Ybira.publicar_file(scope, file.public_id)
      assert {:ok, _file} = Ybira.tirar_file_da_praca(scope, file.public_id)

      assert {:ok, %{events: events}} = Maraca.list_events(scope)
      zones = for event <- events, event.type in [:published_to_praca, :moved_between_zones], do: event
      assert length(zones) == 2
      assert Enum.all?(zones, &(&1.payload["name"] == "estatuto.pdf"))
    end

    test "pedido, aprovação e negação de acesso registram o vaivém", %{
      tekoa: tekoa,
      zelador: zelador,
      morador: morador
    } do
      owner_scope = Scope.new(zelador, tekoa)
      path = tmp_upload_fixture("segredo", "diario.txt")
      assert {:ok, file} = Ybira.upload(owner_scope, path, filename: "diario.txt")

      assert {:ok, request} =
               Maraca.request_access(morador, zelador, "ybira_file", file.public_id, "quero ler")

      assert {:ok, _permission} = Maraca.approve_access_request(zelador, request.id)

      path2 = tmp_upload_fixture("outro segredo", "caixa.txt")
      assert {:ok, file2} = Ybira.upload(owner_scope, path2, filename: "caixa.txt")

      assert {:ok, request2} = Maraca.request_access(morador, zelador, "ybira_file", file2.public_id, "quero ler")
      assert {:ok, _request} = Maraca.deny_access_request(zelador, request2.id)

      assert {:ok, %{events: events}} = Maraca.list_events(owner_scope)
      types = Enum.map(events, & &1.type)
      assert :access_requested in types
      assert :access_granted in types
      assert :access_denied in types
    end

    test "desativar conta registra a conta desativada", %{tekoa: tekoa, zelador: zelador, morador: morador} do
      scope = Scope.new(zelador, tekoa)

      assert {:ok, _member} = Maraca.deactivate_member(scope, morador.public_id)

      assert {:ok, %{events: [event]}} = Maraca.list_events(scope)
      assert event.type == :member_deactivated
      assert event.payload["member"] == "Bruno"
    end

    test "mudança de papel registra o membro e o papel novo", %{tekoa: tekoa, zelador: zelador, morador: morador} do
      scope = Scope.new(zelador, tekoa)

      assert {:ok, _member} = Maraca.update_member_role(scope, morador.public_id, :zelador)

      assert {:ok, %{events: [event]}} = Maraca.list_events(scope)
      assert event.type == :member_role_changed
      assert event.payload["member"] == "Bruno"
      assert event.payload["role"] == "zelador"
    end

    test "reativar conta registra a conta reativada", %{tekoa: tekoa, zelador: zelador, morador: morador} do
      scope = Scope.new(zelador, tekoa)
      assert {:ok, _member} = Maraca.deactivate_member(scope, morador.public_id)
      assert {:ok, _member} = Maraca.reactivate_member(scope, morador.public_id)

      # O mais novo vem primeiro: [member_reactivated, member_deactivated].
      assert {:ok, %{events: [reactivated, deactivated]}} = Maraca.list_events(scope)
      assert reactivated.type == :member_reactivated
      assert reactivated.payload["member"] == "Bruno"
      assert deactivated.type == :member_deactivated
    end

    test "mudança de cota registra de quanto para quanto", %{tekoa: tekoa, zelador: zelador} do
      scope = Scope.new(zelador, tekoa)

      assert {:ok, _tekoa} = Maraca.update_tekoa_quota(scope, 5 * 1024 ** 3)

      assert {:ok, %{events: [event]}} = Maraca.list_events(scope)
      assert event.type == :quota_changed
      assert event.payload["from"] == tekoa.storage_quota_bytes
      assert event.payload["to"] == 5 * 1024 ** 3
    end
  end
end
