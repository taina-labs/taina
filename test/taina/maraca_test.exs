defmodule Taina.MaracaTest do
  use Taina.DataCase, async: true

  import Ecto.Query
  import Plug.Test
  import Taina.Fixtures

  alias Taina.Maraca
  alias Taina.Repo
  alias Taina.Scope
  alias Taina.Ybira
  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Concessao
  alias Ypy.Maraca.Pedido

  @tipo_file "ypy.file.v0"

  describe "bootstrap/2" do
    test "creates the single tekoa and an active zelador, com a chave da cadeia" do
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
      assert tekoa.domain
      assert zelador.papel == :zelador
      assert zelador.username == "fundadora"
      assert zelador.display_name == "Fundadora"
      assert Maraca.activated?(zelador)
      assert zelador.password_hash

      # A chave que assina a cadeia nasce com a Tekoa (consulta de sistema).
      assert Repo.exists?(
               from(k in Ypy.Maraca.TekoaKey, where: k.tekoa_id == ^tekoa.id),
               skip_tekoa_id: true
             )
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
      assert {:ok, %{ava: invited, token: token}} = Maraca.invite_user(zelador, tekoa)
      assert token
      assert invited.papel == :morador
      refute Maraca.activated?(invited)
      assert is_nil(invited.username)

      assert {:ok, accepted} =
               Maraca.accept_invite(token, %{
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
      {:ok, %{token: token}} = Maraca.invite_user(zelador, tekoa)

      assert {:ok, accepted} =
               Maraca.accept_invite(token, %{
                 "username" => "  Maria  ",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })

      assert accepted.username == "maria"
    end

    test "password confirmation mismatch is rejected", %{tekoa: tekoa, zelador: zelador} do
      {:ok, %{token: token}} = Maraca.invite_user(zelador, tekoa)

      assert {:error, :invalid_token} =
               Maraca.accept_invite(token, %{
                 "username" => "maria",
                 "password" => "senhasegura123",
                 "password_confirmation" => "outra-coisa"
               })
    end

    test "convite de conta desativada não é aceito", %{tekoa: tekoa, zelador: zelador} do
      {:ok, %{ava: invited, token: token}} = Maraca.invite_user(zelador, tekoa)
      {:ok, _} = Maraca.deactivate_member(Scope.new(zelador, tekoa), invited.public_id)

      assert {:error, :invalid_token} =
               Maraca.accept_invite(token, %{
                 "username" => "maria",
                 "password" => "senhasegura123",
                 "password_confirmation" => "senhasegura123"
               })
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
      {:ok, %{ava: invited, token: token}} = Maraca.invite_user(zelador, tekoa)

      eight_days_ago = DateTime.shift(DateTime.utc_now(), day: -8)

      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok,
         invited
         |> Ecto.Changeset.change(invite_sent_at: DateTime.truncate(eight_days_ago, :second))
         |> Repo.update!()}
      end)

      assert {:error, :invalid_token} =
               Maraca.accept_invite(token, %{
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
      assert session.papel == :morador
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

      assert {:ok, %{token: token}} = Maraca.mint_reset_link(scope, member)

      assert {:ok, _} = Maraca.reset_password(token, "novasenha123", "novasenha123")
      assert {:ok, _} = Maraca.authenticate("maria", "novasenha123", tekoa)
    end

    test "a morador cannot mint a reset link", %{tekoa: tekoa, member: member} do
      morador = active_ava_fixture(tekoa)
      scope = Scope.new(morador, tekoa)

      assert {:error, :unauthorized} = Maraca.mint_reset_link(scope, member)
    end

    test "expired reset token is rejected", %{tekoa: tekoa, zelador: zelador, member: member} do
      scope = Scope.new(zelador, tekoa)
      {:ok, %{ava: with_token}} = Maraca.mint_reset_link(scope, member)

      two_hours_ago = DateTime.shift(DateTime.utc_now(), hour: -2)

      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok,
         with_token
         |> Ecto.Changeset.change(reset_sent_at: DateTime.truncate(two_hours_ago, :second))
         |> Repo.update!()}
      end)

      assert {:error, :invalid_token} =
               Maraca.reset_password("token_qualquer", "novasenha123", "novasenha123")
    end

    test "senhas diferentes sao erro do formulario, nao link vencido", %{
      tekoa: tekoa,
      zelador: zelador,
      member: member
    } do
      {:ok, %{token: token}} = Maraca.mint_reset_link(Scope.new(zelador, tekoa), member)

      assert {:error, :password_mismatch} =
               Maraca.reset_password(token, "novasenha123", "outrasenha123")
    end

    test "quem resetou perde os aparelhos: o reset nao tem aparelho de chamada", %{
      tekoa: tekoa,
      zelador: zelador,
      member: member
    } do
      scope = Scope.new(zelador, tekoa)
      {:ok, %{token: token}} = Maraca.mint_reset_link(scope, member)

      member_scope = Scope.new(member, tekoa)
      {:ok, %{token: raw}} = Maraca.create_device_token(member_scope, "celular da pessoa")
      assert {:ok, _} = Maraca.resolve_device_token(raw)

      assert {:ok, _} = Maraca.reset_password(token, "novasenha123", "novasenha123")

      # o token do celular da pessoa cai junto (a web e o shell nao tem
      # aparelho de chamada: todos os aparelhos caem)
      assert {:error, :not_authenticated} = Maraca.resolve_device_token(raw)
    end
  end

  describe "update_password/3 (self-service)" do
    setup do
      tekoa = tekoa_fixture()
      ava = active_ava_fixture(tekoa, %{username: "maria", password: "senhasegura123"})
      %{tekoa: tekoa, ava: ava}
    end

    test "troca a senha com a atual certa e a nova entra no lugar", %{tekoa: tekoa, ava: ava} do
      scope = Scope.new(ava, tekoa)

      assert {:ok, updated} = Maraca.update_password(scope, "senhasegura123", "senha-nova-456")
      refute updated.password_hash == ava.password_hash

      assert {:ok, _} = Maraca.authenticate("maria", "senha-nova-456", tekoa)
      assert {:error, :invalid_credentials} = Maraca.authenticate("maria", "senhasegura123", tekoa)
    end

    test "senha atual errada recusa com invalid_credentials", %{tekoa: tekoa, ava: ava} do
      assert {:error, :invalid_credentials} =
               Maraca.update_password(Scope.new(ava, tekoa), "senha-incorreta", "senha-nova-456")

      # a senha antiga segue valendo
      assert {:ok, _} = Maraca.authenticate("maria", "senhasegura123", tekoa)
    end

    test "senha nova curta volta changeset (regra do kernel)", %{tekoa: tekoa, ava: ava} do
      assert {:error, %Ecto.Changeset{}} =
               Maraca.update_password(Scope.new(ava, tekoa), "senhasegura123", "curta")
    end

    test "senha nova que nao e texto volta changeset, sem chegar ao banco", %{tekoa: tekoa, ava: ava} do
      scope = Scope.new(ava, tekoa)

      assert {:error, %Ecto.Changeset{}} = Maraca.update_password(scope, "senhasegura123", nil)
      assert {:error, %Ecto.Changeset{}} = Maraca.update_password(scope, "senhasegura123", %{"a" => 1})

      # a senha atual segue valendo (nada foi gravado)
      assert {:ok, _} = Maraca.authenticate("maria", "senhasegura123", tekoa)
    end

    test "senha atual que nao e texto nao chega ao bcrypt: invalid_credentials", %{tekoa: tekoa, ava: ava} do
      scope = Scope.new(ava, tekoa)

      assert {:error, :invalid_credentials} = Maraca.update_password(scope, nil, "senha-nova-456")
      assert {:error, :invalid_credentials} = Maraca.update_password(scope, %{"a" => 1}, "senha-nova-456")
      assert {:error, :invalid_credentials} = Maraca.update_password(scope, 42, "senha-nova-456")

      # a senha antiga segue valendo
      assert {:ok, _} = Maraca.authenticate("maria", "senhasegura123", tekoa)
    end

    test "a conferencia da senha atual queima a janela do login (o mesmo limite do authenticate)", %{
      tekoa: tekoa,
      ava: ava
    } do
      scope = Scope.new(ava, tekoa)

      # o limite do login: 5 tentativas erradas na janela
      for _ <- 1..5 do
        assert {:error, :invalid_credentials} = Maraca.update_password(scope, "errada", "senha-nova-456")
      end

      # estourou: nem a senha CORRETA passa, a conferencia nem roda
      assert {:error, :rate_limited} = Maraca.update_password(scope, "senhasegura123", "senha-nova-456")

      # e o login da conta compartilha a mesma janela
      assert {:error, :rate_limited} = Maraca.authenticate("maria", "senhasegura123", tekoa)
    end

    test "queima um link de reset pendente", %{tekoa: tekoa, ava: ava} do
      zelador = zelador_fixture(tekoa)
      {:ok, %{token: token}} = Maraca.mint_reset_link(Scope.new(zelador, tekoa), ava)

      assert {:ok, _} = Maraca.update_password(Scope.new(ava, tekoa), "senhasegura123", "senha-nova-456")

      assert {:error, :invalid_token} = Maraca.reset_password(token, "terceira789", "terceira789")
    end
  end

  describe "authorize?/4 and concessoes" do
    setup do
      tekoa = tekoa_fixture()
      owner = active_ava_fixture(tekoa)
      other = active_ava_fixture(tekoa)
      {:ok, ybira_file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())

      %{
        tekoa: tekoa,
        owner: owner,
        other: other,
        ybira_file: ybira_file,
        owner_scope: Scope.new(owner, tekoa)
      }
    end

    test "owner is always authorized", %{owner: owner, ybira_file: ybira_file} do
      assert Maraca.authorize?(owner, :read, @tipo_file, ybira_file.rkey)
      assert Maraca.authorize?(owner, :delete, @tipo_file, ybira_file.rkey)
    end

    test "others are denied by default, including zeladores", %{tekoa: tekoa, other: other, ybira_file: ybira_file} do
      zelador = zelador_fixture(tekoa)

      refute Maraca.authorize?(other, :read, @tipo_file, ybira_file.rkey)
      refute Maraca.authorize?(zelador, :read, @tipo_file, ybira_file.rkey)
    end

    test "concessao explicita grants read access; write stays with the owner", %{
      owner_scope: owner_scope,
      other: other,
      ybira_file: ybira_file
    } do
      assert {:ok, %Concessao{dono_id: dono_id, leitor_id: leitor_id}} =
               Maraca.conceder(owner_scope, @tipo_file, ybira_file.rkey, other)

      assert dono_id == owner_scope.ava.id
      assert leitor_id == other.id
      assert Maraca.authorize?(other, :read, @tipo_file, ybira_file.rkey)
      refute Maraca.authorize?(other, :write, @tipo_file, ybira_file.rkey)
    end

    test "authorize!/4 raises when denied", %{other: other, ybira_file: ybira_file} do
      assert_raise Taina.Maraca.UnauthorizedError, fn ->
        Maraca.authorize!(other, :read, @tipo_file, ybira_file.rkey)
      end
    end

    test "only the owner concede", %{other: other, tekoa: tekoa, ybira_file: ybira_file} do
      stranger = active_ava_fixture(tekoa)

      assert {:error, :not_owner} =
               Maraca.conceder(Scope.new(stranger, tekoa), @tipo_file, ybira_file.rkey, other)
    end

    test "revoke by owner removes access", %{owner_scope: owner_scope, other: other, ybira_file: ybira_file} do
      {:ok, concessao} = Maraca.conceder(owner_scope, @tipo_file, ybira_file.rkey, other)

      assert {:ok, _} = Maraca.revogar(owner_scope, concessao)
      refute Maraca.authorize?(other, :read, @tipo_file, ybira_file.rkey)
      assert {:error, :invalid_status} = Maraca.revogar(owner_scope, concessao)
    end

    test "third parties cannot revoke", %{tekoa: tekoa, owner: owner, other: other, ybira_file: ybira_file} do
      stranger = active_ava_fixture(tekoa)
      {:ok, concessao} = Maraca.conceder(Scope.new(owner, tekoa), @tipo_file, ybira_file.rkey, other)

      assert {:error, :not_authorized} = Maraca.revogar(Scope.new(stranger, tekoa), concessao)
    end
  end

  describe "access requests" do
    setup do
      tekoa = tekoa_fixture()
      owner = active_ava_fixture(tekoa)
      zelador = zelador_fixture(tekoa)
      {:ok, ybira_file} = Ybira.upload(Scope.new(owner, tekoa), tmp_upload_fixture())

      %{
        tekoa: tekoa,
        owner: owner,
        zelador: zelador,
        ybira_file: ybira_file,
        owner_scope: Scope.new(owner, tekoa),
        zelador_scope: Scope.new(zelador, tekoa)
      }
    end

    test "zelador requests, owner aprova, a concessao aparece", %{
      owner: owner,
      zelador: zelador,
      ybira_file: ybira_file,
      owner_scope: owner_scope,
      zelador_scope: zelador_scope
    } do
      assert {:ok, %Pedido{status: :pendente} = pedido} =
               Maraca.pedir_acesso(zelador_scope, @tipo_file, ybira_file.rkey, "Ticket #123")

      assert pedido.pedinte_id == zelador.id

      assert {:ok, %Concessao{dono_id: dono_id}} = Maraca.aprovar(owner_scope, pedido)

      assert dono_id == owner.id
      assert Maraca.authorize?(zelador, :read, @tipo_file, ybira_file.rkey)
    end

    test "owner can negar; pedido fica registrado", %{
      ybira_file: ybira_file,
      owner_scope: owner_scope,
      zelador_scope: zelador_scope
    } do
      {:ok, pedido} = Maraca.pedir_acesso(zelador_scope, @tipo_file, ybira_file.rkey, "Auditoria")

      assert {:ok, %Pedido{status: :negado}} = Maraca.negar(owner_scope, pedido)
      refute Maraca.authorize?(zelador_scope.ava, :read, @tipo_file, ybira_file.rkey)
      assert {:error, :not_pending} = Maraca.negar(owner_scope, pedido)
    end

    test "any morador can request access (RFC_003 D4)", %{tekoa: tekoa, ybira_file: ybira_file} do
      morador = active_ava_fixture(tekoa)

      assert {:ok, %Pedido{status: :pendente, pedinte_id: pedinte_id}} =
               Maraca.pedir_acesso(Scope.new(morador, tekoa), @tipo_file, ybira_file.rkey, "Por favor")

      assert pedinte_id == morador.id
    end

    test "cannot request access to your own resource", %{owner: owner, tekoa: tekoa, ybira_file: ybira_file} do
      assert {:error, :cannot_request_own} =
               Maraca.pedir_acesso(Scope.new(owner, tekoa), @tipo_file, ybira_file.rkey, "Meu próprio")
    end

    test "quem ja le não pode pedir de novo", %{
      owner_scope: owner_scope,
      zelador_scope: zelador_scope,
      ybira_file: ybira_file
    } do
      {:ok, _concessao} = Maraca.conceder(owner_scope, @tipo_file, ybira_file.rkey, zelador_scope.ava)

      assert {:error, :already_has_access} =
               Maraca.pedir_acesso(zelador_scope, @tipo_file, ybira_file.rkey, "De novo")
    end

    test "only the owner decides", %{
      tekoa: tekoa,
      owner_scope: owner_scope,
      zelador_scope: zelador_scope,
      ybira_file: ybira_file
    } do
      stranger = active_ava_fixture(tekoa)
      {:ok, pedido} = Maraca.pedir_acesso(zelador_scope, @tipo_file, ybira_file.rkey, "Ticket")

      assert {:error, :not_authorized} = Maraca.aprovar(Scope.new(stranger, tekoa), pedido)
      assert {:error, :not_found} = Maraca.aprovar(owner_scope, %Pedido{id: 0})
    end

    test "pedidos_recebidos/1 shows pending for the owner", %{
      zelador: zelador,
      ybira_file: ybira_file,
      owner_scope: owner_scope,
      zelador_scope: zelador_scope
    } do
      {:ok, pedido} = Maraca.pedir_acesso(zelador_scope, @tipo_file, ybira_file.rkey, "Ticket")

      assert {:ok, [pending]} = Maraca.pedidos_recebidos(owner_scope)
      assert pending.id == pedido.id
      assert pending.pedinte.id == zelador.id
    end

    test "pedidos_enviados/1 shows the requests the caller made", %{
      owner: owner,
      owner_scope: owner_scope,
      zelador_scope: zelador_scope,
      ybira_file: ybira_file
    } do
      {:ok, pedido} = Maraca.pedir_acesso(zelador_scope, @tipo_file, ybira_file.rkey, "Ticket")

      assert {:ok, [mine]} = Maraca.pedidos_enviados(zelador_scope)
      assert mine.id == pedido.id
      assert mine.dono.id == owner.id

      assert {:ok, []} = Maraca.pedidos_enviados(owner_scope)
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

      assert updated.papel == :zelador
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
      assert demoted.papel == :morador
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

      # A troca de papel e verbo do kernel: o guarda la dentro responde
      # :not_authorized. (Des)ativar e revogar convite sao ritos do produto,
      # com o :unauthorized daqui.
      assert {:error, :not_authorized} =
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

    test "successful logins never consume the window" do
      tekoa = tekoa_fixture()
      active_ava_fixture(tekoa, %{username: "carla"})

      # Muito acima do limite, sempre com a senha certa: só falhas contam, então
      # nenhuma trava aparece.
      for _ <- 1..(3 * 5) do
        assert {:ok, _} = Maraca.authenticate("carla", "senhasegura123", tekoa)
      end
    end
  end
end
