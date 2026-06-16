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
    test "creates the single tekoa and a confirmed admin" do
      assert {:ok, %{tekoa: tekoa, ava: admin}} =
               Maraca.bootstrap(
                 %{name: "Aldeia Inicial", storage_quota_bytes: 1024},
                 %{
                   username: "fundadora",
                   email: "fundadora@example.com",
                   password: "senhasegura123",
                   password_confirmation: "senhasegura123"
                 }
               )

      assert tekoa.name == "Aldeia Inicial"
      assert admin.role == :admin
      assert Maraca.email_confirmed?(admin)
      assert admin.password_hash
    end

    test "refuses when a tekoa already exists" do
      tekoa_fixture()

      assert {:error, :already_bootstrapped} =
               Maraca.bootstrap(%{name: "Segunda", storage_quota_bytes: 1024}, %{})
    end
  end

  describe "invite_user/4 and confirm_email/4" do
    setup do
      tekoa = tekoa_fixture()
      %{tekoa: tekoa, admin: admin_fixture(tekoa)}
    end

    test "admin invites, raw token confirms the account", %{tekoa: tekoa, admin: admin} do
      assert {:ok, invited} = Maraca.invite_user(admin, tekoa, "nova@example.com")
      assert invited.email_confirmation_token
      refute Maraca.email_confirmed?(invited)

      assert {:ok, confirmed} =
               Maraca.confirm_email(
                 invited.email_confirmation_token,
                 "senhasegura123",
                 "senhasegura123",
                 "maria"
               )

      assert confirmed.username == "maria"
      assert Maraca.email_confirmed?(confirmed)
      assert is_nil(confirmed.email_confirmation_token_hash)
    end

    test "members cannot invite", %{tekoa: tekoa} do
      member = confirmed_ava_fixture(tekoa)

      assert {:error, :not_admin} = Maraca.invite_user(member, tekoa, "x@example.com")
    end

    test "unknown token is rejected" do
      assert {:error, :invalid_token} =
               Maraca.confirm_email("token_invalido", "senha1234", "senha1234", "alguem")
    end

    test "expired invitation token is rejected", %{tekoa: tekoa, admin: admin} do
      {:ok, invited} = Maraca.invite_user(admin, tekoa, "tarde@example.com")

      eight_days_ago = DateTime.add(DateTime.utc_now(), -8, :day)

      invited
      |> Ecto.Changeset.change(email_confirmation_sent_at: eight_days_ago)
      |> Repo.update!()

      assert {:error, :invalid_token} =
               Maraca.confirm_email(
                 invited.email_confirmation_token,
                 "senhasegura123",
                 "senhasegura123",
                 "tarde"
               )
    end
  end

  describe "update_tekoa_quota/2" do
    test "admin updates the storage quota" do
      tekoa = tekoa_fixture()
      admin = admin_fixture(tekoa)
      scope = Scope.new(admin, tekoa)

      assert {:ok, updated} = Maraca.update_tekoa_quota(scope, 5_000)
      assert updated.storage_quota_bytes == 5_000
    end

    test "members are rejected" do
      tekoa = tekoa_fixture()
      member = confirmed_ava_fixture(tekoa)
      scope = Scope.new(member, tekoa)

      assert {:error, :unauthorized} = Maraca.update_tekoa_quota(scope, 5_000)
    end

    test "a non-positive quota fails validation" do
      tekoa = tekoa_fixture()
      admin = admin_fixture(tekoa)
      scope = Scope.new(admin, tekoa)

      assert {:error, changeset} = Maraca.update_tekoa_quota(scope, 0)
      assert "must be greater than 0" in errors_on(changeset).storage_quota_bytes
    end
  end

  describe "authenticate/3" do
    setup do
      tekoa = tekoa_fixture()
      ava = confirmed_ava_fixture(tekoa, %{email: "login@example.com"})
      %{tekoa: tekoa, ava: ava}
    end

    test "valid credentials authenticate", %{tekoa: tekoa, ava: ava} do
      assert {:ok, authenticated} = Maraca.authenticate("login@example.com", "senhasegura123", tekoa)
      assert authenticated.id == ava.id
    end

    test "wrong password is rejected", %{tekoa: tekoa} do
      assert {:error, :invalid_credentials} = Maraca.authenticate("login@example.com", "errada123", tekoa)
    end

    test "unknown email is rejected", %{tekoa: tekoa} do
      assert {:error, :invalid_credentials} = Maraca.authenticate("nao@existe.com", "qualquer123", tekoa)
    end

    test "unconfirmed account cannot log in", %{tekoa: tekoa} do
      ava_fixture(tekoa, %{email: "pendente@example.com"})

      assert {:error, :email_not_confirmed} =
               Maraca.authenticate("pendente@example.com", "qualquer123", tekoa)
    end
  end

  describe "sessions" do
    setup do
      tekoa = tekoa_fixture()
      %{tekoa: tekoa, ava: confirmed_ava_fixture(tekoa)}
    end

    test "create_session/1 exposes only public ids", %{tekoa: tekoa, ava: ava} do
      session = Maraca.create_session(ava)

      assert session.ava_id == ava.public_id
      assert session.tekoa_id == tekoa.public_id
      assert session.role == :member
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

  describe "password reset" do
    setup do
      tekoa = tekoa_fixture()
      %{tekoa: tekoa, ava: confirmed_ava_fixture(tekoa, %{email: "reset@example.com"})}
    end

    test "full reset flow", %{tekoa: tekoa} do
      assert {:ok, %Ava{} = with_token} = Maraca.request_password_reset("reset@example.com", tekoa)
      assert with_token.reset_token

      assert {:ok, _} = Maraca.reset_password(with_token.reset_token, "novasenha123", "novasenha123")
      assert {:ok, _} = Maraca.authenticate("reset@example.com", "novasenha123", tekoa)
    end

    test "unknown email gets the same shaped reply", %{tekoa: tekoa} do
      assert {:ok, :email_sent} = Maraca.request_password_reset("ghost@example.com", tekoa)
    end

    test "expired reset token is rejected", %{tekoa: tekoa} do
      {:ok, with_token} = Maraca.request_password_reset("reset@example.com", tekoa)

      two_hours_ago = DateTime.add(DateTime.utc_now(), -2, :hour)

      with_token
      |> Ecto.Changeset.change(reset_token_sent_at: two_hours_ago)
      |> Repo.update!()

      assert {:error, :invalid_token} =
               Maraca.reset_password(with_token.reset_token, "novasenha123", "novasenha123")
    end
  end

  describe "authorize?/4 and permissions" do
    setup do
      tekoa = tekoa_fixture()
      owner = confirmed_ava_fixture(tekoa)
      other = confirmed_ava_fixture(tekoa)
      {:ok, ybira_file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())
      %{tekoa: tekoa, owner: owner, other: other, ybira_file: ybira_file}
    end

    test "owner is always authorized", %{owner: owner, ybira_file: ybira_file} do
      assert Maraca.authorize?(owner, :read, "ybira_file", ybira_file.public_id)
      assert Maraca.authorize?(owner, :delete, "ybira_file", ybira_file.public_id)
    end

    test "others are denied by default — including admins", %{tekoa: tekoa, other: other, ybira_file: ybira_file} do
      admin = admin_fixture(tekoa)

      refute Maraca.authorize?(other, :read, "ybira_file", ybira_file.public_id)
      refute Maraca.authorize?(admin, :read, "ybira_file", ybira_file.public_id)
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
      stranger = confirmed_ava_fixture(tekoa)
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
      owner = confirmed_ava_fixture(tekoa)
      admin = admin_fixture(tekoa)
      {:ok, ybira_file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())
      %{tekoa: tekoa, owner: owner, admin: admin, ybira_file: ybira_file}
    end

    test "admin requests, owner approves, read permission appears", %{
      owner: owner,
      admin: admin,
      ybira_file: ybira_file
    } do
      assert {:ok, %AccessRequest{status: :pending} = request} =
               Maraca.request_access(admin, owner, "ybira_file", ybira_file.public_id, "Ticket #123")

      assert {:ok, %Permission{action: :read}} = Maraca.approve_access_request(owner, request.id)
      assert Maraca.authorize?(admin, :read, "ybira_file", ybira_file.public_id)
    end

    test "owner can deny; request stays for audit", %{owner: owner, admin: admin, ybira_file: ybira_file} do
      {:ok, request} = Maraca.request_access(admin, owner, "ybira_file", ybira_file.public_id, "Auditoria")

      assert {:ok, %AccessRequest{status: :denied}} = Maraca.deny_access_request(owner, request.id)
      refute Maraca.authorize?(admin, :read, "ybira_file", ybira_file.public_id)
      assert {:error, :invalid_status} = Maraca.deny_access_request(owner, request.id)
    end

    test "members cannot request access", %{tekoa: tekoa, owner: owner, ybira_file: ybira_file} do
      member = confirmed_ava_fixture(tekoa)

      assert {:error, :not_admin} =
               Maraca.request_access(member, owner, "ybira_file", ybira_file.public_id, "Por favor")
    end

    test "admin with existing permission cannot re-request", %{owner: owner, admin: admin, ybira_file: ybira_file} do
      {:ok, _} = Maraca.grant_permission(owner, admin, :read, "ybira_file", ybira_file.public_id)

      assert {:error, :already_has_access} =
               Maraca.request_access(admin, owner, "ybira_file", ybira_file.public_id, "De novo")
    end

    test "only the owner decides", %{tekoa: tekoa, owner: owner, admin: admin, ybira_file: ybira_file} do
      stranger = confirmed_ava_fixture(tekoa)
      {:ok, request} = Maraca.request_access(admin, owner, "ybira_file", ybira_file.public_id, "Ticket")

      assert {:error, :not_owner} = Maraca.approve_access_request(stranger, request.id)
      assert {:error, :not_found} = Maraca.approve_access_request(owner, 0)
    end

    test "list_access_requests/1 shows pending for the owner", %{owner: owner, admin: admin, ybira_file: ybira_file} do
      {:ok, request} = Maraca.request_access(admin, owner, "ybira_file", ybira_file.public_id, "Ticket")

      assert [pending] = Maraca.list_access_requests(owner)
      assert pending.id == request.id
      assert pending.requester.id == admin.id
    end
  end

  describe "member management" do
    setup do
      tekoa = tekoa_fixture()
      admin = admin_fixture(tekoa)
      member = confirmed_ava_fixture(tekoa)
      %{tekoa: tekoa, admin: admin, member: member}
    end

    test "admin lists members; members cannot", %{tekoa: tekoa, admin: admin, member: member} do
      assert {:ok, members} = Maraca.list_members(Scope.new(admin, tekoa))
      assert length(members) == 2
      assert {:error, :unauthorized} = Maraca.list_members(Scope.new(member, tekoa))
    end

    test "admin promotes a member to admin", %{tekoa: tekoa, admin: admin, member: member} do
      assert {:ok, updated} =
               Maraca.update_member_role(Scope.new(admin, tekoa), member.public_id, :admin)

      assert updated.role == :admin
    end

    test "the last active admin cannot be demoted", %{tekoa: tekoa, admin: admin} do
      assert {:error, :last_admin} =
               Maraca.update_member_role(Scope.new(admin, tekoa), admin.public_id, :member)
    end

    test "an admin can be demoted when another active admin remains", %{
      tekoa: tekoa,
      admin: admin,
      member: member
    } do
      scope = Scope.new(admin, tekoa)
      {:ok, _} = Maraca.update_member_role(scope, member.public_id, :admin)

      assert {:ok, demoted} = Maraca.update_member_role(scope, admin.public_id, :member)
      assert demoted.role == :member
    end

    test "deactivate then reactivate a member", %{tekoa: tekoa, admin: admin, member: member} do
      scope = Scope.new(admin, tekoa)

      assert {:ok, deactivated} = Maraca.deactivate_member(scope, member.public_id)
      refute Ava.active?(deactivated)

      assert {:ok, reactivated} = Maraca.reactivate_member(scope, member.public_id)
      assert Ava.active?(reactivated)
    end

    test "the last active admin cannot be deactivated", %{tekoa: tekoa, admin: admin} do
      assert {:error, :last_admin} =
               Maraca.deactivate_member(Scope.new(admin, tekoa), admin.public_id)
    end

    test "members cannot manage members", %{tekoa: tekoa, admin: admin, member: member} do
      scope = Scope.new(member, tekoa)

      assert {:error, :unauthorized} =
               Maraca.update_member_role(scope, admin.public_id, :member)

      assert {:error, :unauthorized} = Maraca.deactivate_member(scope, admin.public_id)
      assert {:error, :unauthorized} = Maraca.reactivate_member(scope, admin.public_id)
    end

    test "unknown member is not found", %{tekoa: tekoa, admin: admin} do
      scope = Scope.new(admin, tekoa)

      assert {:error, :not_found} = Maraca.update_member_role(scope, "nope", :admin)
      assert {:error, :not_found} = Maraca.deactivate_member(scope, "nope")
    end

    test "a deactivated account cannot authenticate", %{tekoa: tekoa, admin: admin} do
      member = confirmed_ava_fixture(tekoa, %{email: "deact@example.com"})
      {:ok, _} = Maraca.deactivate_member(Scope.new(admin, tekoa), member.public_id)

      assert {:error, :account_deactivated} =
               Maraca.authenticate("deact@example.com", "senhasegura123", tekoa)
    end
  end

  describe "login rate limiting" do
    test "blocks after too many attempts for the same (tekoa, email)" do
      tekoa = tekoa_fixture()
      confirmed_ava_fixture(tekoa, %{email: "brute@example.com"})

      # As 5 primeiras tentativas passam (senha errada → :invalid_credentials);
      # a 6ª é barrada pelo limitador.
      for _ <- 1..5 do
        assert {:error, :invalid_credentials} =
                 Maraca.authenticate("brute@example.com", "errada123", tekoa)
      end

      assert {:error, :rate_limited} =
               Maraca.authenticate("brute@example.com", "errada123", tekoa)
    end
  end
end
