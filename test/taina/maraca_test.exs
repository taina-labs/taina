defmodule Taina.MaracaTest do
  use Taina.DataCase, async: true

  import Plug.Test
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Maraca.AccessRequest
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Permission
  alias Taina.Scope
  alias Taina.Ybira

  describe "bootstrap/2" do
    test "creates the single tekoa and an active zelador" do
      assert {:ok, %{tekoa: tekoa, ava: zelador}} =
               Maraca.bootstrap(
                 %{name: "Aldeia Inicial", storage_quota_bytes: 1024},
                 %{
                   username: "fundadora",
                   display_name: "Fundadora",
                   password: "senhasegura123",
                   password_confirmation: "senhasegura123"
                 }
               )

      assert tekoa.name == "Aldeia Inicial"
      assert zelador.role == :zelador
      assert zelador.username == "fundadora"
      assert zelador.display_name == "Fundadora"
      assert Maraca.activated?(zelador)
      assert zelador.password_hash
    end

    test "refuses when a tekoa already exists" do
      tekoa_fixture()

      assert {:error, :already_bootstrapped} =
               Maraca.bootstrap(%{name: "Segunda", storage_quota_bytes: 1024}, %{})
    end
  end

  describe "invite_user/3 and accept_invite/2" do
    setup do
      tekoa = tekoa_fixture()
      %{tekoa: tekoa, zelador: zelador_fixture(tekoa)}
    end

    test "invite carries a token (no e-mail) and accept creates the account", %{tekoa: tekoa, zelador: zelador} do
      assert {:ok, invited} = Maraca.invite_user(zelador, tekoa)
      assert invited.invite_token
      assert invited.role == :morador
      refute Maraca.activated?(invited)
      assert is_nil(invited.username)

      assert {:ok, accepted} =
               Maraca.accept_invite(invited.invite_token, %{
                 "username" => "maria",
                 "display_name" => "Maria Silva",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })

      assert accepted.username == "maria"
      assert accepted.display_name == "Maria Silva"
      assert Maraca.activated?(accepted)
      assert is_nil(accepted.invite_token_hash)
    end

    test "the username is normalized to a handle on accept", %{tekoa: tekoa, zelador: zelador} do
      {:ok, invited} = Maraca.invite_user(zelador, tekoa)

      assert {:ok, accepted} =
               Maraca.accept_invite(invited.invite_token, %{
                 "username" => "  Maria  ",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })

      assert accepted.username == "maria"
    end

    test "a morador cannot invite", %{tekoa: tekoa} do
      morador = active_ava_fixture(tekoa)

      assert {:error, :not_zelador} = Maraca.invite_user(morador, tekoa)
    end

    test "unknown token is rejected" do
      assert {:error, :invalid_token} =
               Maraca.accept_invite("token_invalido", %{
                 "username" => "alguem",
                 "password" => "senha1234",
                 "password_confirmation" => "senha1234"
               })
    end

    test "expired invite token is rejected", %{tekoa: tekoa, zelador: zelador} do
      {:ok, invited} = Maraca.invite_user(zelador, tekoa)

      eight_days_ago = DateTime.add(DateTime.utc_now(), -8, :day)

      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok,
         invited
         |> Ecto.Changeset.change(invite_sent_at: eight_days_ago)
         |> Repo.update!()}
      end)

      assert {:error, :invalid_token} =
               Maraca.accept_invite(invited.invite_token, %{
                 "username" => "tarde",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })
    end
  end

  describe "update_tekoa_quota/2" do
    test "a zelador updates the storage quota" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      scope = Scope.new(zelador, tekoa)

      assert {:ok, updated} = Maraca.update_tekoa_quota(scope, 5_000)
      assert updated.storage_quota_bytes == 5_000
    end

    test "moradores are rejected" do
      tekoa = tekoa_fixture()
      morador = active_ava_fixture(tekoa)
      scope = Scope.new(morador, tekoa)

      assert {:error, :unauthorized} = Maraca.update_tekoa_quota(scope, 5_000)
    end

    test "a non-positive quota fails validation" do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      scope = Scope.new(zelador, tekoa)

      assert {:error, changeset} = Maraca.update_tekoa_quota(scope, 0)
      assert "must be greater than 0" in errors_on(changeset).storage_quota_bytes
    end
  end

  describe "authenticate/3" do
    setup do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa, %{username: "maria"})
      %{tekoa: tekoa, ava: ava}
    end

    test "valid credentials authenticate by username", %{tekoa: tekoa, ava: ava} do
      assert {:ok, authenticated} = Maraca.authenticate("maria", "senhasegura123", tekoa)
      assert authenticated.id == ava.id
    end

    test "login is case-insensitive on the username", %{tekoa: tekoa, ava: ava} do
      assert {:ok, authenticated} = Maraca.authenticate("  MARIA ", "senhasegura123", tekoa)
      assert authenticated.id == ava.id
    end

    test "wrong password is rejected", %{tekoa: tekoa} do
      assert {:error, :invalid_credentials} = Maraca.authenticate("maria", "errada123", tekoa)
    end

    test "unknown username is rejected", %{tekoa: tekoa} do
      assert {:error, :invalid_credentials} = Maraca.authenticate("ninguem", "qualquer123", tekoa)
    end

    test "a pending invite (no password) cannot log in", %{tekoa: tekoa} do
      ava_fixture(tekoa, %{username: "pendente"})

      assert {:error, :invalid_credentials} = Maraca.authenticate("pendente", "qualquer123", tekoa)
    end
  end

  describe "sessions" do
    setup do
      tekoa = tekoa_fixture()
      %{tekoa: tekoa, ava: active_ava_fixture(tekoa)}
    end

    test "create_session/1 exposes only public ids", %{tekoa: tekoa, ava: ava} do
      session = Maraca.create_session(ava)

      assert session.ava_id == ava.public_id
      assert session.tekoa_id == tekoa.public_id
      assert session.role == :morador
    end

    test "get_session_user/1 loads the ava with tekoa", %{ava: ava} do
      conn = :get |> conn("/") |> init_test_session(%{ava_id: ava.public_id})

      assert {:ok, loaded} = Maraca.get_session_user(conn)
      assert loaded.id == ava.id
      assert loaded.tekoa.id == ava.tekoa_id
    end

    test "get_session_user/1 without session" do
      conn = :get |> conn("/") |> init_test_session(%{})

      assert {:error, :not_authenticated} = Maraca.get_session_user(conn)
    end

    test "destroy_session/1 drops the session", %{ava: ava} do
      conn = :get |> conn("/") |> init_test_session(%{ava_id: ava.public_id})

      conn = Maraca.destroy_session(conn)

      assert {:error, :not_authenticated} = Maraca.get_session_user(conn)
    end
  end

  describe "mint_reset_link/2 (recuperação mediada pelo zelador)" do
    setup do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      member = active_ava_fixture(tekoa, %{username: "maria"})
      %{tekoa: tekoa, zelador: zelador, member: member}
    end

    test "zelador mints a link and the member sets a new password", %{tekoa: tekoa, zelador: zelador, member: member} do
      scope = Scope.new(zelador, tekoa)

      assert {:ok, %Ava{} = with_token} = Maraca.mint_reset_link(scope, member)
      assert with_token.reset_token

      assert {:ok, _} = Maraca.reset_password(with_token.reset_token, "novasenha123", "novasenha123")
      assert {:ok, _} = Maraca.authenticate("maria", "novasenha123", tekoa)
    end

    test "a morador cannot mint a reset link", %{tekoa: tekoa, member: member} do
      morador = active_ava_fixture(tekoa)
      scope = Scope.new(morador, tekoa)

      assert {:error, :unauthorized} = Maraca.mint_reset_link(scope, member)
    end

    test "expired reset token is rejected", %{tekoa: tekoa, zelador: zelador, member: member} do
      scope = Scope.new(zelador, tekoa)
      {:ok, with_token} = Maraca.mint_reset_link(scope, member)

      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok,
         with_token
         |> Ecto.Changeset.change(reset_token_sent_at: two_hours_ago)
         |> Repo.update!()}
      end)

      assert {:error, :invalid_token} =
               Maraca.reset_password(with_token.reset_token, "novasenha123", "novasenha123")
    end
  end

  describe "authorize?/4 and permissions" do
    setup do
      tekoa = tekoa_fixture()
      owner = active_ava_fixture(tekoa)
      other = active_ava_fixture(tekoa)
      {:ok, ybira_file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())
      %{tekoa: tekoa, owner: owner, other: other, ybira_file: ybira_file}
    end

    test "owner is always authorized", %{owner: owner, ybira_file: ybira_file} do
      assert Maraca.authorize?(owner, :read, "ybira_file", ybira_file.public_id)
      assert Maraca.authorize?(owner, :delete, "ybira_file", ybira_file.public_id)
    end

    test "others are denied by default, including zeladores", %{tekoa: tekoa, other: other, ybira_file: ybira_file} do
      zelador = zelador_fixture(tekoa)

      refute Maraca.authorize?(other, :read, "ybira_file", ybira_file.public_id)
      refute Maraca.authorize?(zelador, :read, "ybira_file", ybira_file.public_id)
    end

    test "explicit permission grants access", %{owner: owner, other: other, ybira_file: ybira_file} do
      assert {:ok, %Permission{}} =
               Maraca.grant_permission(owner, other, :read, "ybira_file", ybira_file.public_id)

      assert Maraca.authorize?(other, :read, "ybira_file", ybira_file.public_id)
      refute Maraca.authorize?(other, :write, "ybira_file", ybira_file.public_id)
    end

    test "authorize!/4 raises when denied", %{other: other, ybira_file: ybira_file} do
      assert_raise Taina.Maraca.UnauthorizedError, fn ->
        Maraca.authorize!(other, :read, "ybira_file", ybira_file.public_id)
      end
    end

    test "only the owner grants; :share is never grantable", %{
      owner: owner,
      other: other,
      ybira_file: ybira_file
    } do
      assert {:error, :not_owner} =
               Maraca.grant_permission(other, other, :read, "ybira_file", ybira_file.public_id)

      assert {:error, :invalid_action} =
               Maraca.grant_permission(owner, other, :share, "ybira_file", ybira_file.public_id)
    end

    test "revoke by owner removes access", %{owner: owner, other: other, ybira_file: ybira_file} do
      {:ok, _} = Maraca.grant_permission(owner, other, :read, "ybira_file", ybira_file.public_id)

      assert :ok = Maraca.revoke_permission(owner, other, :read, "ybira_file", ybira_file.public_id)
      refute Maraca.authorize?(other, :read, "ybira_file", ybira_file.public_id)
      assert {:error, :not_found} = Maraca.revoke_permission(owner, other, :read, "ybira_file", ybira_file.public_id)
    end

    test "third parties cannot revoke", %{tekoa: tekoa, owner: owner, other: other, ybira_file: ybira_file} do
      stranger = active_ava_fixture(tekoa)
      {:ok, _} = Maraca.grant_permission(owner, other, :read, "ybira_file", ybira_file.public_id)

      assert {:error, :not_authorized} =
               Maraca.revoke_permission(stranger, other, :read, "ybira_file", ybira_file.public_id)
    end

    test "list_permissions/2 returns grants with preloads", %{owner: owner, other: other, ybira_file: ybira_file} do
      {:ok, _} = Maraca.grant_permission(owner, other, :read, "ybira_file", ybira_file.public_id)

      assert [permission] = Maraca.list_permissions("ybira_file", ybira_file.public_id)
      assert permission.ava.id == other.id
      assert permission.granted_by.id == owner.id
    end
  end

  describe "access requests" do
    setup do
      tekoa = tekoa_fixture()
      owner = active_ava_fixture(tekoa)
      zelador = zelador_fixture(tekoa)
      {:ok, ybira_file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())
      %{tekoa: tekoa, owner: owner, zelador: zelador, ybira_file: ybira_file}
    end

    test "zelador requests, owner approves, read permission appears", %{
      owner: owner,
      zelador: zelador,
      ybira_file: ybira_file
    } do
      assert {:ok, %AccessRequest{status: :pending} = request} =
               Maraca.request_access(zelador, owner, "ybira_file", ybira_file.public_id, "Ticket #123")

      assert {:ok, %Permission{action: :read}} = Maraca.approve_access_request(owner, request.id)
      assert Maraca.authorize?(zelador, :read, "ybira_file", ybira_file.public_id)
    end

    test "owner can deny; request stays for audit", %{owner: owner, zelador: zelador, ybira_file: ybira_file} do
      {:ok, request} = Maraca.request_access(zelador, owner, "ybira_file", ybira_file.public_id, "Auditoria")

      assert {:ok, %AccessRequest{status: :denied}} = Maraca.deny_access_request(owner, request.id)
      refute Maraca.authorize?(zelador, :read, "ybira_file", ybira_file.public_id)
      assert {:error, :invalid_status} = Maraca.deny_access_request(owner, request.id)
    end

    test "moradores cannot request access", %{tekoa: tekoa, owner: owner, ybira_file: ybira_file} do
      morador = active_ava_fixture(tekoa)

      assert {:error, :not_zelador} =
               Maraca.request_access(morador, owner, "ybira_file", ybira_file.public_id, "Por favor")
    end

    test "zelador with existing permission cannot re-request", %{owner: owner, zelador: zelador, ybira_file: ybira_file} do
      {:ok, _} = Maraca.grant_permission(owner, zelador, :read, "ybira_file", ybira_file.public_id)

      assert {:error, :already_has_access} =
               Maraca.request_access(zelador, owner, "ybira_file", ybira_file.public_id, "De novo")
    end

    test "only the owner decides", %{tekoa: tekoa, owner: owner, zelador: zelador, ybira_file: ybira_file} do
      stranger = active_ava_fixture(tekoa)
      {:ok, request} = Maraca.request_access(zelador, owner, "ybira_file", ybira_file.public_id, "Ticket")

      assert {:error, :not_owner} = Maraca.approve_access_request(stranger, request.id)
      assert {:error, :not_found} = Maraca.approve_access_request(owner, 0)
    end

    test "list_access_requests/1 shows pending for the owner", %{owner: owner, zelador: zelador, ybira_file: ybira_file} do
      {:ok, request} = Maraca.request_access(zelador, owner, "ybira_file", ybira_file.public_id, "Ticket")

      assert [pending] = Maraca.list_access_requests(owner)
      assert pending.id == request.id
      assert pending.requester.id == zelador.id
    end
  end

  describe "member management" do
    setup do
      tekoa = tekoa_fixture()
      zelador = zelador_fixture(tekoa)
      member = active_ava_fixture(tekoa)
      %{tekoa: tekoa, zelador: zelador, member: member}
    end

    test "zelador promotes a morador to zelador", %{tekoa: tekoa, zelador: zelador, member: member} do
      assert {:ok, updated} =
               Maraca.update_member_role(Scope.new(zelador, tekoa), member.public_id, :zelador)

      assert updated.role == :zelador
    end

    test "the last active zelador cannot be demoted", %{tekoa: tekoa, zelador: zelador} do
      assert {:error, :last_zelador} =
               Maraca.update_member_role(Scope.new(zelador, tekoa), zelador.public_id, :morador)
    end

    test "a zelador can be demoted when another active zelador remains", %{
      tekoa: tekoa,
      zelador: zelador,
      member: member
    } do
      scope = Scope.new(zelador, tekoa)
      {:ok, _} = Maraca.update_member_role(scope, member.public_id, :zelador)

      assert {:ok, demoted} = Maraca.update_member_role(scope, zelador.public_id, :morador)
      assert demoted.role == :morador
    end

    test "deactivate then reactivate a member", %{tekoa: tekoa, zelador: zelador, member: member} do
      scope = Scope.new(zelador, tekoa)

      assert {:ok, deactivated} = Maraca.deactivate_member(scope, member.public_id)
      refute Ava.active?(deactivated)

      assert {:ok, reactivated} = Maraca.reactivate_member(scope, member.public_id)
      assert Ava.active?(reactivated)
    end

    test "the last active zelador cannot be deactivated", %{tekoa: tekoa, zelador: zelador} do
      assert {:error, :last_zelador} =
               Maraca.deactivate_member(Scope.new(zelador, tekoa), zelador.public_id)
    end

    test "moradores cannot manage members", %{tekoa: tekoa, zelador: zelador, member: member} do
      scope = Scope.new(member, tekoa)

      assert {:error, :unauthorized} =
               Maraca.update_member_role(scope, zelador.public_id, :morador)

      assert {:error, :unauthorized} = Maraca.deactivate_member(scope, zelador.public_id)
      assert {:error, :unauthorized} = Maraca.reactivate_member(scope, zelador.public_id)
    end

    test "unknown member is not found", %{tekoa: tekoa, zelador: zelador} do
      scope = Scope.new(zelador, tekoa)

      assert {:error, :not_found} = Maraca.update_member_role(scope, "nope", :zelador)
      assert {:error, :not_found} = Maraca.deactivate_member(scope, "nope")
    end

    test "a deactivated account cannot authenticate", %{tekoa: tekoa, zelador: zelador} do
      member = active_ava_fixture(tekoa, %{username: "deact"})
      {:ok, _} = Maraca.deactivate_member(Scope.new(zelador, tekoa), member.public_id)

      assert {:error, :account_deactivated} =
               Maraca.authenticate("deact", "senhasegura123", tekoa)
    end
  end

  describe "login rate limiting" do
    test "blocks after too many attempts for the same (tekoa, username)" do
      tekoa = tekoa_fixture()
      active_ava_fixture(tekoa, %{username: "brute"})

      # As 5 primeiras tentativas passam (senha errada -> :invalid_credentials);
      # a 6a e barrada pelo limitador.
      for _ <- 1..5 do
        assert {:error, :invalid_credentials} =
                 Maraca.authenticate("brute", "errada123", tekoa)
      end

      assert {:error, :rate_limited} =
               Maraca.authenticate("brute", "errada123", tekoa)
    end
  end
end
