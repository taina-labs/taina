defmodule Taina.MaracaDeviceTokenTest do
  use Taina.DataCase, async: true

  import Ecto.Query
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Maraca.DeviceToken
  alias Taina.Repo
  alias Taina.Scope

  # Conta ativa: a resolucao do token revalida a conta, entao um convite
  # pendente (o `scope_fixture/0`) nao resolve, de proposito.
  defp active_scope do
    tekoa = tekoa_fixture()
    Scope.new(active_ava_fixture(tekoa), tekoa)
  end

  defp tokens_for(tekoa_id) do
    Repo.all(from(d in DeviceToken, where: d.tekoa_id == ^tekoa_id), skip_tekoa_id: true)
  end

  describe "create_device_token/2" do
    test "devolve o segredo cru uma vez e guarda so o hash" do
      scope = active_scope()

      assert {:ok, %{device: device, token: raw}} =
               Maraca.create_device_token(scope, "celular da ana")

      assert String.starts_with?(raw, "tnd_")
      assert String.length(raw) == 4 + 32
      assert device.ava_id == scope.ava.id
      assert device.tekoa_id == scope.tekoa.id

      [row] = tokens_for(scope.tekoa.id)
      assert row.name == "celular da ana"
      refute row.token_hash == raw
      refute String.contains?(row.token_hash, raw)
    end

    test "rotulo vazio ou longo demais nao passa" do
      scope = active_scope()

      assert {:error, %Ecto.Changeset{}} = Maraca.create_device_token(scope, "")
      assert {:error, %Ecto.Changeset{}} = Maraca.create_device_token(scope, String.duplicate("a", 81))
    end
  end

  describe "resolve_device_token/1" do
    test "resolve um token valido no scope e no dispositivo" do
      scope = active_scope()
      {:ok, %{device: device, token: raw}} = Maraca.create_device_token(scope, "tablet")

      assert {:ok, %{scope: resolved, device: found}} = Maraca.resolve_device_token(raw)
      assert found.id == device.id
      assert resolved.ava.id == scope.ava.id
      assert resolved.tekoa.id == scope.tekoa.id
    end

    test "nao resolve token desconhecido nem lixo" do
      active_scope()

      assert {:error, :not_authenticated} = Maraca.resolve_device_token("tnd_nao_existe")
      assert {:error, :not_authenticated} = Maraca.resolve_device_token(nil)
    end

    test "nao resolve token revogado" do
      scope = active_scope()
      {:ok, %{device: device, token: raw}} = Maraca.create_device_token(scope, "antigo")

      assert {:ok, _} = Maraca.revoke_device(scope, device.public_id)
      assert {:error, :not_authenticated} = Maraca.resolve_device_token(raw)
    end

    test "conta desativada nao resolve; reativada, os tokens antigos voltam" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)
      scope = Scope.new(morador, tekoa)

      {:ok, %{token: raw}} = Maraca.create_device_token(scope, "celular")
      assert {:ok, _} = Maraca.resolve_device_token(raw)

      zelador_scope = Scope.new(zelador, tekoa)
      assert {:ok, _} = Maraca.deactivate_member(zelador_scope, morador.public_id)
      assert {:error, :not_authenticated} = Maraca.resolve_device_token(raw)

      assert {:ok, _} = Maraca.reactivate_member(zelador_scope, morador.public_id)
      assert {:ok, _} = Maraca.resolve_device_token(raw)
    end

    test "last_used_at so e escrito quando passa da janela de 5 minutos" do
      scope = active_scope()
      {:ok, %{token: raw}} = Maraca.create_device_token(scope, "celular")

      assert {:ok, %{device: first}} = Maraca.resolve_device_token(raw)
      assert %DateTime{} = first.last_used_at

      assert {:ok, %{device: second}} = Maraca.resolve_device_token(raw)
      assert second.last_used_at == first.last_used_at

      old = DateTime.utc_now() |> DateTime.shift(minute: -10) |> DateTime.truncate(:second)

      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        {:ok,
         Repo.update_all(
           from(d in DeviceToken, where: d.tekoa_id == ^scope.tekoa.id),
           set: [last_used_at: old]
         )}
      end)

      assert {:ok, %{device: third}} = Maraca.resolve_device_token(raw)
      assert DateTime.after?(third.last_used_at, old)
    end
  end

  describe "list_devices/1" do
    test "lista so os dispositivos de quem esta agindo, do mais recente para o mais antigo" do
      tekoa = tekoa_fixture()
      ana = active_ava_fixture(tekoa)
      bia = active_ava_fixture(tekoa)

      {:ok, %{device: first}} = Maraca.create_device_token(Scope.new(ana, tekoa), "primeiro")
      {:ok, %{device: second}} = Maraca.create_device_token(Scope.new(ana, tekoa), "segundo")
      {:ok, _} = Maraca.create_device_token(Scope.new(bia, tekoa), "da bia")

      assert {:ok, devices} = Maraca.list_devices(Scope.new(ana, tekoa))
      assert Enum.map(devices, & &1.id) == [second.id, first.id]
    end
  end

  describe "revoke_device/2" do
    test "a dona revoga o proprio dispositivo, de forma idempotente" do
      scope = active_scope()
      {:ok, %{device: device}} = Maraca.create_device_token(scope, "celular")

      assert {:ok, revoked} = Maraca.revoke_device(scope, device.public_id)
      assert %DateTime{} = revoked.revoked_at

      assert {:ok, again} = Maraca.revoke_device(scope, device.public_id)
      assert again.revoked_at == revoked.revoked_at
    end

    test "a zeladora revoga o dispositivo de outra pessoa" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      morador = active_ava_fixture(tekoa)
      {:ok, %{device: device}} = Maraca.create_device_token(Scope.new(morador, tekoa), "celular")

      assert {:ok, revoked} = Maraca.revoke_device(Scope.new(zelador, tekoa), device.public_id)
      assert %DateTime{} = revoked.revoked_at
    end

    test "outro morador nao revoga o dispositivo alheio" do
      tekoa = tekoa_fixture()
      ana = active_ava_fixture(tekoa)
      bia = active_ava_fixture(tekoa)
      {:ok, %{device: device}} = Maraca.create_device_token(Scope.new(ana, tekoa), "celular")

      assert {:error, :unauthorized} = Maraca.revoke_device(Scope.new(bia, tekoa), device.public_id)
    end

    test "id desconhecido ou malformado e not_found" do
      scope = active_scope()

      assert {:error, :not_found} = Maraca.revoke_device(scope, "nao_existe")
      assert {:error, :not_found} = Maraca.revoke_device(scope, "AAAAAAAAAAAA")
    end
  end
end
