defmodule Taina.Maraca do
  @moduledoc """
  Interface pública para autenticação e autorização do serviço Maraca.

  Implementa `Taina.Maraca.Behaviour` — consulte cada callback para regras de
  negócio detalhadas.

  ## Filosofia

  - **Usuários são donos de seus dados** - Propriedade explícita
  - **Admins são facilitadores, não deuses** - Devem solicitar acesso
  - **Permissões explícitas** - Nunca implícitas
  - **Auditabilidade total** - Todas as tentativas de acesso registradas

  ## Convites sem e-mail

  Conforme a RFC 002 (D6), convites são por **link**: `invite_user/4` retorna
  o Ava com o token cru no campo virtual `email_confirmation_token` — o
  chamador monta a URL/QR code e entrega pelo canal que a comunidade já usa.
  E-mail (Swoosh) é opcional e fica para depois.

  ## Ordem de Resolução de Permissões

  1. **Isolamento de comunidade** (RLS garante tekoa_id)
  2. **Propriedade do recurso** (ava_id == resource.ava_id)
  3. **Permissões explícitas** (tabela maraca.permissions)
  4. **Negação padrão** (se nada acima, acesso negado)
  """

  @behaviour Taina.Maraca.Behaviour

  import Ecto.Query

  alias Ecto.Changeset
  alias Taina.Maraca.AccessRequest
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Permission
  alias Taina.Maraca.Tekoa
  alias Taina.Maraca.UnauthorizedError
  alias Taina.Repo
  alias Taina.Scope

  @invitation_max_age_seconds 7 * 24 * 60 * 60
  @reset_max_age_seconds 60 * 60
  @grantable_actions ~w(read write delete)a

  # Mapa de tipos de recurso → {schema, campo de dono}. A propriedade é o
  # segundo nível da resolução de permissões; tipos fora deste mapa só podem
  # ser autorizados por permissão explícita.
  @owned_resources %{
    "ybira_file" => {Taina.Ybira.File, :ava_id},
    "ybira_folder" => {Taina.Ybira.Folder, :ava_id},
    "guara_chat" => {Taina.Guara.Chat, :created_by_id}
  }

  ## Bootstrap

  @impl true
  def bootstrap(tekoa_attrs, admin_attrs) do
    if Repo.exists?(Tekoa, skip_tekoa_id: true) do
      {:error, :already_bootstrapped}
    else
      Repo.transact(fn -> create_tekoa_with_admin(tekoa_attrs, admin_attrs) end)
    end
  end

  defp create_tekoa_with_admin(tekoa_attrs, admin_attrs) do
    with {:ok, tekoa} <- Repo.insert(Tekoa.changeset(%Tekoa{}, tekoa_attrs)),
         {:ok, ava} <- insert_bootstrap_admin(tekoa, admin_attrs) do
      {:ok, %{tekoa: tekoa, ava: ava}}
    end
  end

  defp insert_bootstrap_admin(%Tekoa{} = tekoa, attrs) do
    base = %{
      username: attrs[:username],
      email: attrs[:email],
      role: :admin,
      tekoa_id: tekoa.id
    }

    %Ava{}
    |> Ava.changeset(base)
    |> Ava.confirmation_changeset(Map.take(attrs, [:username, :password, :password_confirmation]))
    |> Repo.insert()
  end

  ## Convite e confirmação

  @impl true
  def invite_user(%Ava{} = admin, %Tekoa{} = tekoa, email, opts \\ []) do
    if admin?(admin) and admin.tekoa_id == tekoa.id do
      attrs = %{
        email: email,
        tekoa_id: tekoa.id,
        invited_by_id: admin.id,
        role: Keyword.get(opts, :role, :member)
      }

      Repo.with_tekoa(tekoa.public_id, fn ->
        Repo.insert(Ava.invitation_changeset(%Ava{}, attrs))
      end)
    else
      {:error, :not_admin}
    end
  end

  @impl true
  def confirm_email(token, password, password_confirmation, username) do
    with %Ava{} = ava <- find_by_token(:email_confirmation_token_hash, token),
         false <- token_expired?(ava.email_confirmation_sent_at, @invitation_max_age_seconds) do
      attrs = %{username: username, password: password, password_confirmation: password_confirmation}

      Repo.with_tekoa(tekoa_public_id(ava), fn ->
        Repo.update(Ava.confirmation_changeset(ava, attrs))
      end)
    else
      _ -> {:error, :invalid_token}
    end
  end

  ## Autenticação e sessão

  @impl true
  def authenticate(email, password, %Tekoa{} = tekoa) do
    {:ok, result} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok, Repo.get_by(Ava, email: email, tekoa_id: tekoa.id)}
      end)

    verify_credentials(result, password)
  end

  defp verify_credentials(nil, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp verify_credentials(%Ava{confirmed_at: nil}, _password) do
    Bcrypt.no_user_verify()
    {:error, :email_not_confirmed}
  end

  defp verify_credentials(%Ava{} = ava, password) do
    if Bcrypt.verify_pass(password, ava.password_hash) do
      {:ok, ava}
    else
      {:error, :invalid_credentials}
    end
  end

  @impl true
  def create_session(%Ava{} = ava) do
    %{ava_id: ava.public_id, tekoa_id: tekoa_public_id(ava), role: ava.role}
  end

  @impl true
  def destroy_session(%Plug.Conn{} = conn) do
    conn
    |> Plug.Conn.clear_session()
    |> Plug.Conn.configure_session(drop: true)
  end

  @impl true
  def get_session_user(%Plug.Conn{} = conn) do
    conn |> Plug.Conn.get_session(:ava_id) |> resolve_session_ava()
  end

  # LiveView `on_mount` recebe o mapa de sessão (chaves string), não a conn.
  def get_session_user(%{"ava_id" => ava_id}), do: resolve_session_ava(ava_id)
  def get_session_user(_session), do: {:error, :not_authenticated}

  defp resolve_session_ava(public_id) when is_binary(public_id) do
    case Repo.get_by(Ava, [public_id: public_id], skip_tekoa_id: true) do
      %Ava{} = ava ->
        tekoa = Repo.get!(Tekoa, ava.tekoa_id, skip_tekoa_id: true)
        {:ok, %{ava | tekoa: tekoa}}

      _ ->
        {:error, :not_authenticated}
    end
  end

  defp resolve_session_ava(_public_id), do: {:error, :not_authenticated}

  ## Gestão da Tekoa

  @impl true
  def update_tekoa_quota(%Scope{} = scope, quota_bytes) when is_integer(quota_bytes) do
    if admin?(scope.ava) do
      Repo.with_tekoa(scope.tekoa.public_id, fn ->
        Tekoa
        |> Repo.get!(scope.tekoa.id)
        |> Tekoa.changeset(%{storage_quota_bytes: quota_bytes})
        |> Repo.update()
      end)
    else
      {:error, :unauthorized}
    end
  end

  ## Reset de senha

  @impl true
  def request_password_reset(email, %Tekoa{} = tekoa) do
    Repo.with_tekoa(tekoa.public_id, fn ->
      case Repo.get_by(Ava, email: email, tekoa_id: tekoa.id) do
        nil -> {:ok, :email_sent}
        %Ava{} = ava -> Repo.update(Ava.password_reset_request_changeset(ava))
      end
    end)
  end

  @impl true
  def reset_password(reset_token, new_password, password_confirmation) do
    with %Ava{} = ava <- find_by_token(:reset_token_hash, reset_token),
         false <- token_expired?(ava.reset_token_sent_at, @reset_max_age_seconds) do
      attrs = %{password: new_password, password_confirmation: password_confirmation}

      Repo.with_tekoa(tekoa_public_id(ava), fn ->
        Repo.update(Ava.password_reset_changeset(ava, attrs))
      end)
    else
      _ -> {:error, :invalid_token}
    end
  end

  ## Autorização

  @impl true
  def authorize?(%Ava{} = ava, action, resource_type, resource_id)
      when is_atom(action) and is_binary(resource_type) and is_binary(resource_id) do
    {:ok, authorized?} =
      Repo.with_tekoa(tekoa_public_id(ava), fn ->
        {:ok,
         owner_of?(ava, resource_type, resource_id) or
           has_permission?(ava, action, resource_type, resource_id)}
      end)

    authorized?
  end

  @impl true
  def authorize!(%Ava{} = ava, action, resource_type, resource_id) do
    if authorize?(ava, action, resource_type, resource_id) do
      :ok
    else
      raise UnauthorizedError,
        ava: ava,
        action: action,
        resource_type: resource_type,
        resource_id: resource_id
    end
  end

  @impl true
  def grant_permission(%Ava{} = granter, %Ava{} = recipient, action, resource_type, resource_id) do
    if action in @grantable_actions do
      Repo.with_tekoa(tekoa_public_id(granter), fn ->
        insert_grant(granter, recipient, action, resource_type, resource_id)
      end)
    else
      {:error, :invalid_action}
    end
  end

  defp insert_grant(granter, recipient, action, resource_type, resource_id) do
    if owner_of?(granter, resource_type, resource_id) do
      %Permission{}
      |> Permission.changeset(%{
        ava_id: recipient.id,
        resource_type: resource_type,
        resource_id: resource_id,
        action: action
      })
      |> Changeset.put_change(:granted_by_id, granter.id)
      |> Changeset.put_change(:tekoa_id, granter.tekoa_id)
      |> Repo.insert()
    else
      {:error, :not_owner}
    end
  end

  @impl true
  def revoke_permission(%Ava{} = revoker, %Ava{} = recipient, action, resource_type, resource_id) do
    result =
      Repo.with_tekoa(tekoa_public_id(revoker), fn ->
        permission =
          Repo.get_by(Permission,
            ava_id: recipient.id,
            action: action,
            resource_type: resource_type,
            resource_id: resource_id
          )

        revoke_if_allowed(permission, revoker, resource_type, resource_id)
      end)

    with {:ok, :revoked} <- result, do: :ok
  end

  defp revoke_if_allowed(nil, _revoker, _type, _id), do: {:error, :not_found}

  defp revoke_if_allowed(%Permission{} = permission, revoker, resource_type, resource_id) do
    if owner_of?(revoker, resource_type, resource_id) or permission.granted_by_id == revoker.id do
      Repo.delete!(permission)
      {:ok, :revoked}
    else
      {:error, :not_authorized}
    end
  end

  @impl true
  def list_permissions(resource_type, resource_id) do
    query =
      from p in Permission,
        where: p.resource_type == ^resource_type,
        where: p.resource_id == ^resource_id

    query
    |> Repo.all(skip_tekoa_id: true)
    |> Repo.preload([:ava, :granted_by], skip_tekoa_id: true)
  end

  ## Acesso administrativo (com aprovação do dono)

  @impl true
  def request_access(%Ava{} = admin, %Ava{} = owner, resource_type, resource_id, reason) do
    cond do
      not admin?(admin) ->
        {:error, :not_admin}

      authorize?(admin, :read, resource_type, resource_id) ->
        {:error, :already_has_access}

      true ->
        attrs = %{
          requester_id: admin.id,
          owner_id: owner.id,
          resource_type: resource_type,
          resource_id: resource_id,
          reason: reason,
          tekoa_id: admin.tekoa_id
        }

        result =
          Repo.with_tekoa(tekoa_public_id(admin), fn ->
            Repo.insert(AccessRequest.create_changeset(%AccessRequest{}, attrs))
          end)

        with {:ok, request} <- result do
          notify(owner.public_id, {:access_requested, request})
          {:ok, request}
        end
    end
  end

  @impl true
  def approve_access_request(%Ava{} = owner, access_request_id) do
    result =
      Repo.with_tekoa(tekoa_public_id(owner), fn ->
        with {:ok, request} <- fetch_pending_request(owner, access_request_id),
             {:ok, _request} <- Repo.update(AccessRequest.changeset(request, %{status: :approved})) do
          %Permission{}
          |> Permission.changeset(%{
            ava_id: request.requester_id,
            resource_type: request.resource_type,
            resource_id: request.resource_id,
            action: :read
          })
          |> Changeset.put_change(:granted_by_id, owner.id)
          |> Changeset.put_change(:tekoa_id, owner.tekoa_id)
          |> Repo.insert()
        end
      end)

    with {:ok, permission} <- result do
      notify_requester(permission.ava_id, {:access_request_approved, permission})
      {:ok, permission}
    end
  end

  @impl true
  def deny_access_request(%Ava{} = owner, access_request_id) do
    result =
      Repo.with_tekoa(tekoa_public_id(owner), fn ->
        with {:ok, request} <- fetch_pending_request(owner, access_request_id) do
          Repo.update(AccessRequest.changeset(request, %{status: :denied}))
        end
      end)

    with {:ok, request} <- result do
      notify_requester(request.requester_id, {:access_request_denied, request})
      {:ok, request}
    end
  end

  defp fetch_pending_request(%Ava{} = owner, access_request_id) do
    case Repo.get(AccessRequest, access_request_id) do
      nil -> {:error, :not_found}
      %AccessRequest{owner_id: owner_id} when owner_id != owner.id -> {:error, :not_owner}
      %AccessRequest{status: :pending} = request -> {:ok, request}
      %AccessRequest{} -> {:error, :invalid_status}
    end
  end

  @impl true
  def list_access_requests(%Ava{} = owner) do
    {:ok, requests} =
      Repo.with_tekoa(tekoa_public_id(owner), fn ->
        query =
          from r in AccessRequest,
            where: r.owner_id == ^owner.id,
            where: r.status == :pending,
            order_by: [desc: r.inserted_at],
            preload: [:requester]

        {:ok, Repo.all(query)}
      end)

    requests
  end

  ## Predicados

  @impl true
  def admin?(%Ava{role: :admin}), do: true
  def admin?(%Ava{}), do: false

  @impl true
  def email_confirmed?(%Ava{confirmed_at: nil}), do: false
  def email_confirmed?(%Ava{}), do: true

  ## Helpers internos

  defp owner_of?(%Ava{} = ava, resource_type, resource_id) do
    case Map.fetch(@owned_resources, resource_type) do
      {:ok, {schema, owner_field}} ->
        case Repo.get_by(schema, public_id: resource_id) do
          nil -> false
          resource -> Map.fetch!(resource, owner_field) == ava.id
        end

      :error ->
        false
    end
  end

  defp has_permission?(%Ava{} = ava, action, resource_type, resource_id) do
    query =
      from p in Permission,
        where: p.ava_id == ^ava.id,
        where: p.action == ^action,
        where: p.resource_type == ^resource_type,
        where: p.resource_id == ^resource_id

    Repo.exists?(query)
  end

  defp find_by_token(hash_field, token) when is_binary(token) do
    Repo.get_by(Ava, [{hash_field, Ava.hash_token(token)}], skip_tekoa_id: true)
  end

  defp find_by_token(_hash_field, _token), do: nil

  defp token_expired?(nil, _max_age), do: true

  defp token_expired?(%DateTime{} = sent_at, max_age_seconds) do
    DateTime.diff(DateTime.utc_now(), sent_at) > max_age_seconds
  end

  defp tekoa_public_id(%Ava{tekoa: %Tekoa{public_id: public_id}}), do: public_id

  defp tekoa_public_id(%Ava{tekoa_id: tekoa_id}) do
    Repo.get!(Tekoa, tekoa_id, skip_tekoa_id: true).public_id
  end

  defp notify_requester(requester_ava_id, message) do
    case Repo.get(Ava, requester_ava_id, skip_tekoa_id: true) do
      nil -> :ok
      %Ava{} = requester -> notify(requester.public_id, message)
    end
  end

  defp notify(ava_public_id, message) do
    Phoenix.PubSub.broadcast(Taina.PubSub, "maraca:ava:" <> ava_public_id, message)
  end
end
