defmodule Taina.Maraca do
  @moduledoc """
  Interface pública para autenticação e autorização do serviço Maraca.

  Implementa `Taina.Maraca.Behaviour`, consulte cada callback para regras de
  negócio detalhadas.

  ## Filosofia

  - **Moradores são donos de seus dados** - Propriedade explícita
  - **Zeladores cuidam da máquina, não são deuses** - Devem pedir acesso
  - **Permissões explícitas** - Nunca implícitas
  - **Auditabilidade total** - Todas as tentativas de acesso registradas

  ## Identidade sem e-mail (RFC_003, seção 4)

  Convites são por **link/QR**: `invite_user/3` cria um Ava pendente e devolve
  o token cru no campo virtual `invite_token`; o chamador monta a URL/QR e
  entrega pelo canal que a comunidade já usa. Não há e-mail: login é por nome
  (`username`) e a recuperação é mediada pelo zelador (`mint_reset_link/2`).

  ## Ordem de Resolução de Permissões

  1. **Isolamento de comunidade** (RLS garante tekoa_id)
  2. **Propriedade do recurso** (ava_id == resource.ava_id)
  3. **Permissões explícitas** (tabela maraca.permissions)
  4. **Negação padrão** (se nada acima, acesso negado)
  """

  @behaviour Taina.Maraca.Behaviour

  import Ecto.Query

  alias Taina.Maraca.AccessRequest
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Event
  alias Taina.Maraca.Permission
  alias Taina.Maraca.Tekoa
  alias Taina.Maraca.UnauthorizedError
  alias Taina.RateLimit
  alias Taina.Repo
  alias Taina.Scope

  require Logger

  @invitation_max_age_seconds 7 * 24 * 60 * 60
  @reset_max_age_seconds 60 * 60
  @grantable_actions ~w(read write delete)a
  @event_page_limit 50

  # Janela de força bruta de login, por (tekoa, username): no máximo
  # @login_rate_limit tentativas a cada @login_rate_scale_ms. Folgado o
  # suficiente para erros de digitação, apertado contra enumeração de senha.
  @login_rate_scale_ms 60_000
  @login_rate_limit 5

  # Mapa de tipos de recurso -> {schema, campo de dono}. A propriedade é o
  # segundo nível da resolução de permissões; tipos fora deste mapa só podem
  # ser autorizados por permissão explícita.
  @owned_resources %{
    "ybira_file" => {Taina.Ybira.File, :ava_id},
    "ybira_folder" => {Taina.Ybira.Folder, :ava_id},
    "guara_chat" => {Taina.Guara.Chat, :created_by_id}
  }

  ## Bootstrap

  @impl true
  def bootstrap(tekoa_attrs, zelador_attrs) do
    # Consulta e escrita de sistema: roda antes de haver qualquer contexto
    # RLS (a Tekoa nem existe ainda), então cruza as políticas pela válvula.
    # A checagem de existência entra na mesma transação do insert: duas
    # inicializações concorrentes não podem ambas passar do `if`.
    Repo.with_system(fn ->
      if Repo.exists?(Tekoa, skip_tekoa_id: true) do
        {:error, :already_bootstrapped}
      else
        create_tekoa_with_zelador(tekoa_attrs, zelador_attrs)
      end
    end)
  end

  defp create_tekoa_with_zelador(tekoa_attrs, zelador_attrs) do
    with {:ok, tekoa} <- Repo.insert(Tekoa.changeset(%Tekoa{}, tekoa_attrs)),
         {:ok, ava} <- insert_bootstrap_zelador(tekoa, zelador_attrs) do
      {:ok, %{tekoa: tekoa, ava: ava}}
    end
  end

  defp insert_bootstrap_zelador(%Tekoa{} = tekoa, attrs) do
    base = %{
      username: attrs[:username],
      display_name: attrs[:display_name],
      role: :zelador,
      tekoa_id: tekoa.id
    }

    %Ava{}
    |> Ava.changeset(base)
    |> Ava.accept_invite_changeset(Map.take(attrs, [:username, :display_name, :password, :password_confirmation]))
    |> Repo.insert()
  end

  @impl true
  def bootstrapped? do
    # Consulta de sistema: sem a válvula, o papel de aplicação (RLS ativo)
    # veria zero Tekoas e responderia "não bootstrapado" para sempre.
    {:ok, exists?} =
      Repo.with_system(fn -> {:ok, Repo.exists?(Tekoa, skip_tekoa_id: true)} end)

    exists?
  end

  @impl true
  def get_tekoa do
    Repo.with_system(fn ->
      case Repo.one(Tekoa, skip_tekoa_id: true) do
        %Tekoa{} = tekoa -> {:ok, tekoa}
        nil -> {:error, :not_bootstrapped}
      end
    end)
  end

  ## Membros

  @impl true
  def list_members(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      members =
        Repo.all(
          from a in Ava,
            where: a.tekoa_id == ^scope.tekoa.id,
            order_by: [asc: fragment("CASE WHEN ? = 'zelador' THEN 0 ELSE 1 END", a.role), asc: a.inserted_at]
        )

      {:ok, members}
    end)
  end

  @impl true
  def count_members(%Scope{} = scope) do
    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      {:ok, Repo.aggregate(from(a in Ava, where: a.tekoa_id == ^scope.tekoa.id), :count)}
    end)
  end

  ## Convite e aceite

  @impl true
  def invite_user(%Ava{} = zelador, %Tekoa{} = tekoa, opts \\ []) do
    if zelador?(zelador) and zelador.tekoa_id == tekoa.id do
      attrs = %{
        tekoa_id: tekoa.id,
        invited_by_id: zelador.id,
        role: Keyword.get(opts, :role, :morador)
      }

      result =
        Repo.with_tekoa(tekoa.public_id, fn ->
          Repo.insert(Ava.invitation_changeset(%Ava{}, attrs))
        end)

      # O mural registra o convite só depois do ato commitar: a escrita do
      # ledger é consequência, falhar nela não desfaz o convite.
      with {:ok, _ava} <- result do
        record_event(tekoa.public_id, zelador.id, :invite_created, %{
          "role" => Atom.to_string(attrs.role)
        })
      end

      result
    else
      {:error, :not_zelador}
    end
  end

  @impl true
  def accept_invite(token, attrs) do
    with %Ava{} = ava <- find_by_token(:invite_token_hash, token),
         false <- token_expired?(ava.invite_sent_at, @invitation_max_age_seconds),
         # Convite de conta já desativada não vale: sem isto, "desativar" um
         # convite pendente não invalidava o link e a pessoa aceitava para cair
         # numa conta que não consegue logar.
         nil <- ava.deactivated_at do
      tekoa_public_id = tekoa_public_id(ava)

      result =
        Repo.with_tekoa(tekoa_public_id, fn ->
          Repo.update(Ava.accept_invite_changeset(ava, attrs))
        end)

      # Registro do mural depois da transação do aceite: uma falha na escrita
      # do ledger não pode derrubar a conta que acabou de ser criada. O papel
      # vai no payload para o aceite de um zelador ser legível na hora da
      # concessão (o papel é o do convite, decidido em `invite_user/3`).
      with {:ok, _accepted} <- result do
        record_event(tekoa_public_id, ava.id, :invite_accepted, %{
          "role" => Atom.to_string(ava.role)
        })
      end

      result
    else
      _ -> {:error, :invalid_token}
    end
  end

  @impl true
  # Um convite pendente cujo token já passou da validade: a tela de moradores
  # marca como expirado em vez de "aguardando a pessoa aceitar" para sempre.
  def invite_expired?(%Ava{} = ava) do
    token_expired?(ava.invite_sent_at, @invitation_max_age_seconds)
  end

  ## Autenticação e sessão

  @impl true
  def authenticate(username, password, %Tekoa{} = tekoa) do
    username = normalize_username(username)
    key = login_rate_key(tekoa, username)

    if login_rate_exceeded?(key) do
      {:error, :rate_limited}
    else
      case do_authenticate(username, password, tekoa) do
        {:ok, ava} -> {:ok, ava}
        {:error, _reason} = error -> record_login_failure(key, error)
      end
    end
  end

  defp do_authenticate(username, password, %Tekoa{} = tekoa) do
    {:ok, result} =
      Repo.with_tekoa(tekoa.public_id, fn ->
        {:ok, Repo.get_by(Ava, username: username, tekoa_id: tekoa.id)}
      end)

    verify_credentials(result, password)
  end

  defp login_rate_key(%Tekoa{} = tekoa, username), do: "login:#{tekoa.public_id}:#{username}"

  # Só as falhas contam para a janela: lemos a contagem sem incrementar, então
  # uma senha correta nunca a queima (login/logout/login não tranca ninguém).
  # Acima do limite recusamos antes do bcrypt, blindando a CPU contra força
  # bruta. Conta inexistente compartilha a janela do username (não vaza existência).
  defp login_rate_exceeded?(key) do
    RateLimit.get(key, @login_rate_scale_ms) >= @login_rate_limit
  end

  defp record_login_failure(key, error) do
    _ = RateLimit.hit(key, @login_rate_scale_ms, @login_rate_limit)
    error
  end

  defp verify_credentials(nil, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  # Conta desativada pelo zelador: bloqueia login mesmo com senha correta.
  defp verify_credentials(%Ava{deactivated_at: deactivated_at}, _password) when not is_nil(deactivated_at) do
    Bcrypt.no_user_verify()
    {:error, :account_deactivated}
  end

  # Convite ainda não aceito: sem senha definida, não há o que verificar.
  defp verify_credentials(%Ava{password_hash: nil}, _password) do
    Bcrypt.no_user_verify()
    {:error, :invalid_credentials}
  end

  defp verify_credentials(%Ava{} = ava, password) do
    if Bcrypt.verify_pass(password, ava.password_hash) do
      {:ok, ava}
    else
      {:error, :invalid_credentials}
    end
  end

  defp normalize_username(username) do
    username |> to_string() |> String.trim() |> String.downcase()
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

  # Revalida a cada request/mount: uma conta desativada pelo zelador deixa de
  # resolver, então a sessão ainda aberta cai no próximo acesso -- honra o
  # "não vai mais conseguir entrar" da tela de membros. Consulta de sistema
  # (`skip_tekoa_id: true` + válvula): roda antes de haver contexto RLS, no
  # request que o próprio contexto constrói.
  defp resolve_session_ava(public_id) when is_binary(public_id) do
    Repo.with_system(fn ->
      case Repo.get_by(Ava, [public_id: public_id], skip_tekoa_id: true) do
        %Ava{deactivated_at: nil} = ava ->
          tekoa = Repo.get!(Tekoa, ava.tekoa_id, skip_tekoa_id: true)
          {:ok, %{ava | tekoa: tekoa}}

        _ ->
          {:error, :not_authenticated}
      end
    end)
  end

  defp resolve_session_ava(_public_id), do: {:error, :not_authenticated}

  ## Gestão da Tekoa

  @impl true
  def update_tekoa_quota(%Scope{} = scope, quota_bytes) when is_integer(quota_bytes) do
    if zelador?(scope.ava) do
      result =
        Repo.with_tekoa(scope.tekoa.public_id, fn ->
          Tekoa
          |> Repo.get!(scope.tekoa.id)
          |> Tekoa.changeset(%{storage_quota_bytes: quota_bytes})
          |> Repo.update()
        end)

      with {:ok, _tekoa} <- result do
        record_event(scope.tekoa.public_id, scope.ava.id, :quota_changed, %{
          "from" => scope.tekoa.storage_quota_bytes,
          "to" => quota_bytes
        })
      end

      result
    else
      {:error, :unauthorized}
    end
  end

  ## Gestão de membros (zelador)

  @impl true
  def update_member_role(%Scope{} = scope, member_public_id, role) do
    with :ok <- ensure_zelador(scope) do
      result = Repo.with_tekoa(scope.tekoa.public_id, fn -> do_update_role(member_public_id, role) end)

      with {:ok, member} <- result do
        record_event(scope.tekoa.public_id, scope.ava.id, :member_role_changed, %{
          "member" => ava_name(member),
          "role" => Atom.to_string(role)
        })
      end

      result
    end
  end

  @impl true
  def deactivate_member(%Scope{} = scope, member_public_id) do
    with :ok <- ensure_zelador(scope) do
      result = Repo.with_tekoa(scope.tekoa.public_id, fn -> do_deactivate(member_public_id) end)

      with {:ok, member} <- result do
        record_event(scope.tekoa.public_id, scope.ava.id, :member_deactivated, %{
          "member" => ava_name(member)
        })
      end

      result
    end
  end

  @impl true
  def reactivate_member(%Scope{} = scope, member_public_id) do
    with :ok <- ensure_zelador(scope) do
      result = Repo.with_tekoa(scope.tekoa.public_id, fn -> do_reactivate(member_public_id) end)

      with {:ok, member} <- result do
        record_event(scope.tekoa.public_id, scope.ava.id, :member_reactivated, %{
          "member" => ava_name(member)
        })
      end

      result
    end
  end

  @impl true
  def revoke_invite(%Scope{} = scope, member_public_id) do
    with :ok <- ensure_zelador(scope) do
      result = Repo.with_tekoa(scope.tekoa.public_id, fn -> do_revoke_invite(member_public_id) end)

      with {:ok, member} <- result do
        record_event(scope.tekoa.public_id, scope.ava.id, :invite_revoked, %{
          "role" => Atom.to_string(member.role)
        })
      end

      result
    end
  end

  defp do_revoke_invite(public_id) do
    with {:ok, member} <- fetch_member(public_id),
         :ok <- ensure_pending_invite(member) do
      # O convite pendente não tem identidade nem dados (nada aponta para ele),
      # então revogar apaga a linha. Um soft-delete deixaria um "morador" sem
      # nome na lista para sempre.
      Repo.delete(member)
    end
  end

  # Só convite ainda não aceito é revogável. Conta já ativada se remove com
  # desativar (soft): apagar a linha levaria os eventos e as permissões junto
  # (`on_delete: :delete_all`) e sumiria com o histórico.
  defp ensure_pending_invite(%Ava{activated_at: nil}), do: :ok
  defp ensure_pending_invite(%Ava{}), do: {:error, :not_pending}

  defp ensure_zelador(%Scope{ava: ava}) do
    if zelador?(ava), do: :ok, else: {:error, :unauthorized}
  end

  defp do_update_role(public_id, role) do
    with {:ok, member} <- fetch_member(public_id),
         :ok <- ensure_demotion_keeps_zelador(member, role) do
      Repo.update(Ava.role_changeset(member, role))
    end
  end

  defp do_deactivate(public_id) do
    with {:ok, member} <- fetch_member(public_id) do
      deactivate_if_allowed(member)
    end
  end

  defp do_reactivate(public_id) do
    with {:ok, member} <- fetch_member(public_id) do
      Repo.update(Ava.deactivation_changeset(member, nil))
    end
  end

  # Resolve um membro pelo public_id dentro do contexto de Tekoa (RLS escopa por
  # comunidade -- public_id de outra Tekoa simplesmente não aparece).
  defp fetch_member(public_id) do
    case Repo.get_by(Ava, public_id: public_id) do
      nil -> {:error, :not_found}
      %Ava{} = ava -> {:ok, ava}
    end
  end

  # Idempotente: conta já desativada não muda. O último zelador ativo não pode
  # ser desativado (a comunidade ficaria sem quem cuida da máquina).
  defp deactivate_if_allowed(%Ava{deactivated_at: at} = member) when not is_nil(at) do
    {:ok, member}
  end

  defp deactivate_if_allowed(%Ava{} = member) do
    if last_active_zelador?(member) do
      {:error, :last_zelador}
    else
      Repo.update(Ava.deactivation_changeset(member, DateTime.utc_now()))
    end
  end

  # Rebaixar zelador -> morador só é barrado quando esvaziaria a administração.
  defp ensure_demotion_keeps_zelador(%Ava{role: :zelador} = member, :morador) do
    if last_active_zelador?(member), do: {:error, :last_zelador}, else: :ok
  end

  defp ensure_demotion_keeps_zelador(_member, _role), do: :ok

  # `member` é o único zelador ativo da Tekoa? Só faz sentido quando ele próprio
  # é um zelador já ativado; nesse caso, contagem == 1 significa que é o último.
  # Um convite pendente de zelador não conta: a pessoa ainda não entrou.
  defp last_active_zelador?(%Ava{role: :zelador, activated_at: activated_at, deactivated_at: nil})
       when not is_nil(activated_at), do: active_zelador_count() == 1

  defp last_active_zelador?(%Ava{}), do: false

  # Trava os zeladores ativos com FOR UPDATE para serializar desativações e
  # rebaixamentos concorrentes: dois zeladores se removendo ao mesmo tempo não
  # podem ambos ler count == 2 e zerar a administração -- o segundo bloqueia,
  # relê após o commit do primeiro e enxerga count == 1. Roda sempre dentro da
  # transação de `Repo.with_tekoa`. `count(*)` não aceita FOR UPDATE no Postgres,
  # então travamos as linhas e contamos no Elixir (teto de 50 membros, custo trivial).
  # Só conta zelador já ativado: um convite pendente de zelador não é gente ainda.
  defp active_zelador_count do
    from(a in Ava,
      where: a.role == :zelador and is_nil(a.deactivated_at) and not is_nil(a.activated_at),
      lock: "FOR UPDATE",
      select: a.id
    )
    |> Repo.all()
    |> length()
  end

  ## Reset de senha

  @impl true
  def mint_reset_link(%Scope{} = scope, %Ava{} = member) do
    if zelador?(scope.ava) do
      result = Repo.with_tekoa(scope.tekoa.public_id, fn -> do_mint_reset_link(scope, member) end)

      # O registro vai no mural depois da transação, com o nome do membro para
      # quem o link foi gerado (padrão dos demais atos do zelador).
      with {:ok, %Ava{} = with_token} <- result do
        record_event(scope.tekoa.public_id, scope.ava.id, :reset_link_created, %{
          "member" => ava_name(with_token)
        })
      end

      result
    else
      {:error, :unauthorized}
    end
  end

  defp do_mint_reset_link(%Scope{} = scope, %Ava{} = member) do
    case Repo.get_by(Ava, public_id: member.public_id, tekoa_id: scope.tekoa.id) do
      nil -> {:error, :not_found}
      %Ava{} = ava -> Repo.update(Ava.password_reset_request_changeset(ava))
    end
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

  @doc """
  Pode `ava` ler este recurso ja carregado? Regra de leitura das duas zonas
  (RFC_003 D2): `praca OU dono OU permissao explicita`. O zelador nao tem atalho.

  Recebe a `zona` e o `owner_id` que o chamador (Ybira/Jaci) ja tem em maos no
  struct, entao nao re-consulta o dono e so toca a tabela de permissoes como
  ultimo recurso. Difere de `authorize?/4`, que resolve o dono por `public_id` e
  desconhece zona; aqui a zona e a parte nova e o motor (dono OU permissao)
  continua o mesmo.

  Roda dentro do `with_tekoa` do chamador (a consulta de permissao precisa do
  contexto RLS); chame-a so de dentro de um `Repo.with_tekoa/2` ja aberto.
  """
  @impl true
  @spec can_read?(Ava.t(), :casa | :praca, integer(), String.t(), String.t()) :: boolean()
  def can_read?(%Ava{} = ava, zona, owner_id, resource_type, public_id)
      when zona in ~w(casa praca)a and is_integer(owner_id) and is_binary(resource_type) and is_binary(public_id) do
    zona == :praca or ava.id == owner_id or
      has_permission?(ava, :read, resource_type, public_id)
  end

  @doc """
  Filtro de leitura para listagens, regra das duas zonas (RFC_003 D2) no nivel da
  query, sem N+1. Devolve um `Ecto.Query.dynamic` que so deixa passar linhas
  legiveis por `ava`: `zona == :praca OU ava_id == ava.id OU public_id em
  permissoes(:read)`.

  O chamador deve marcar o schema do recurso com `as: :readable` no `from` e
  aplicar `where: ^Maraca.readable_dynamic(ava, resource_type)`. A subconsulta de
  permissoes nao depende do binding externo, entao funciona tanto numa listagem
  simples (Ybira) quanto numa que faz `select` de mapa (linha do tempo do Jaci).

  Pressupoe o contexto RLS aberto (`with_tekoa`); a subconsulta de permissoes e
  escopada por Tekoa pelas policies.
  """
  @impl true
  @spec readable_dynamic(Ava.t(), String.t()) :: Ecto.Query.dynamic_expr()
  def readable_dynamic(%Ava{} = ava, resource_type) when is_binary(resource_type) do
    permitted =
      from p in Permission,
        where: p.ava_id == ^ava.id,
        where: p.action == :read,
        where: p.resource_type == ^resource_type,
        select: p.resource_id

    dynamic(
      [readable: r],
      r.zona == :praca or r.ava_id == ^ava.id or r.public_id in subquery(permitted)
    )
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
      |> Permission.grant_changeset(%{
        ava_id: recipient.id,
        resource_type: resource_type,
        resource_id: resource_id,
        action: action,
        granted_by_id: granter.id,
        tekoa_id: granter.tekoa_id
      })
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
    # Listagem de sistema: o zelador vê as permissões de um recurso cruzando
    # o contexto (quem pode ler um arquivo de outro, por exemplo, não é
    # visível pela policy do próprio solicitante).
    {:ok, permissions} =
      Repo.with_system(fn ->
        permissions =
          from(p in Permission,
            where: p.resource_type == ^resource_type,
            where: p.resource_id == ^resource_id
          )
          |> Repo.all(skip_tekoa_id: true)
          |> Repo.preload([:ava, :granted_by], skip_tekoa_id: true)

        {:ok, permissions}
      end)

    permissions
  end

  ## Acesso do zelador (com aprovação do dono)

  @impl true
  def request_access(%Ava{} = requester, %Ava{} = owner, resource_type, resource_id, reason) do
    cond do
      owner.tekoa_id != requester.tekoa_id ->
        {:error, :cross_tekoa_owner}

      requester.id == owner.id ->
        {:error, :cannot_request_own}

      authorize?(requester, :read, resource_type, resource_id) ->
        {:error, :already_has_access}

      true ->
        attrs = %{
          requester_id: requester.id,
          owner_id: owner.id,
          resource_type: resource_type,
          resource_id: resource_id,
          reason: reason,
          tekoa_id: requester.tekoa_id
        }

        result =
          Repo.with_tekoa(tekoa_public_id(requester), fn ->
            Repo.insert(AccessRequest.create_changeset(%AccessRequest{}, attrs))
          end)

        with {:ok, request} <- result do
          record_event(tekoa_public_id(requester), requester.id, :access_requested, %{
            "owner" => ava_name(owner)
          })

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
          |> Permission.grant_changeset(%{
            ava_id: request.requester_id,
            resource_type: request.resource_type,
            resource_id: request.resource_id,
            action: :read,
            granted_by_id: owner.id,
            tekoa_id: owner.tekoa_id
          })
          |> Repo.insert()
        end
      end)

    with {:ok, permission} <- result do
      requester = system_ava(permission.ava_id)

      record_event(tekoa_public_id(owner), owner.id, :access_granted, %{
        "requester" => ava_name(requester)
      })

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
      requester = system_ava(request.requester_id)

      record_event(tekoa_public_id(owner), owner.id, :access_denied, %{
        "requester" => ava_name(requester)
      })

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

  @impl true
  def list_my_requests(%Ava{} = requester) do
    {:ok, requests} =
      Repo.with_tekoa(tekoa_public_id(requester), fn ->
        query =
          from r in AccessRequest,
            where: r.requester_id == ^requester.id,
            where: r.status == :pending,
            order_by: [desc: r.inserted_at],
            preload: [:owner]

        {:ok, Repo.all(query)}
      end)

    requests
  end

  @impl true
  def subscribe_to_my_events(%Ava{public_id: pid}) do
    Phoenix.PubSub.subscribe(Taina.PubSub, "maraca:ava:" <> pid)
  end

  ## Mural (transparência, RFC_003 seção 6)

  @impl true
  def record_event(tekoa_public_id, ava_id, type, payload)
      when is_binary(tekoa_public_id) and (is_integer(ava_id) or is_nil(ava_id)) do
    result =
      Repo.with_tekoa(tekoa_public_id, fn ->
        case Repo.get_by(Tekoa, public_id: tekoa_public_id) do
          %Tekoa{id: tekoa_id} ->
            %Event{}
            |> Event.changeset(%{tekoa_id: tekoa_id, ava_id: ava_id, type: type, payload: payload})
            |> Repo.insert()

          nil ->
            {:error, :tekoa_not_found}
        end
      end)

    case result do
      {:ok, _event} ->
        # Camada 3 da transparência (RFC_003 seção 6): métrica na caixa, sem
        # reporter para fora. O tipo no metadata, nunca ids de tekoa/ava.
        :telemetry.execute([:taina, :maraca, :event], %{count: 1}, %{type: type})
        :ok

      {:error, reason} ->
        Logger.warning("Mural: falha ao registrar evento (o ato já aconteceu), #{inspect(type)}",
          reason: inspect(reason)
        )

        :ok
    end
  rescue
    e ->
      Logger.warning("Mural: exceção ao registrar evento (o ato já aconteceu), #{inspect(type)}",
        reason: inspect(e)
      )

      :ok
  end

  @impl true
  def list_events(%Scope{} = scope, opts \\ []) do
    limit = Keyword.get(opts, :limit, @event_page_limit)
    offset = Keyword.get(opts, :offset, 0)

    Repo.with_tekoa(scope.tekoa.public_id, fn ->
      query =
        from e in Event,
          where: e.tekoa_id == ^scope.tekoa.id,
          order_by: [desc: e.inserted_at, desc: e.id],
          preload: [:ava]

      rows =
        query
        |> limit(^(limit + 1))
        |> offset(^offset)
        |> Repo.all()

      if length(rows) > limit do
        {:ok, %{events: Enum.take(rows, limit), next_offset: offset + limit}}
      else
        {:ok, %{events: rows, next_offset: nil}}
      end
    end)
  end

  ## Predicados

  @impl true
  def zelador?(%Ava{role: :zelador}), do: true
  def zelador?(%Ava{}), do: false

  @impl true
  def morador?(%Ava{role: :morador}), do: true
  def morador?(%Ava{}), do: false

  @impl true
  def activated?(%Ava{activated_at: nil}), do: false
  def activated?(%Ava{}), do: true

  ## Helpers internos

  # Nome social do Ava para as frases do mural: nome de exibição quando existe,
  # senão o nome de usuário. Convite pendente (sem nome ainda) cai em nil e o
  # mural decide o que mostrar.
  defp ava_name(%Ava{} = ava), do: ava.display_name || ava.username
  defp ava_name(_other), do: nil

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
    # Consulta de sistema (`skip_tekoa_id: true` + válvula): usada no login e
    # no aceite/reset, antes de haver contexto RLS -- a busca é justamente o
    # que constrói o contexto.
    {:ok, ava} =
      Repo.with_system(fn ->
        {:ok, Repo.get_by(Ava, [{hash_field, Ava.hash_token(token)}], skip_tekoa_id: true)}
      end)

    ava
  end

  defp find_by_token(_hash_field, _token), do: nil

  defp token_expired?(nil, _max_age), do: true

  defp token_expired?(%DateTime{} = sent_at, max_age_seconds) do
    DateTime.diff(DateTime.utc_now(), sent_at) > max_age_seconds
  end

  defp tekoa_public_id(%Ava{tekoa: %Tekoa{public_id: public_id}}), do: public_id

  defp tekoa_public_id(%Ava{tekoa_id: tekoa_id}) do
    # Consulta de sistema: resolve o public_id da Tekoa antes de abrir o
    # contexto (o contexto é justamente este public_id).
    {:ok, public_id} =
      Repo.with_system(fn ->
        {:ok, Repo.get!(Tekoa, tekoa_id, skip_tekoa_id: true).public_id}
      end)

    public_id
  end

  # Re-busca de Ava fora do contexto de Tekoa, pós-transação (mural e
  # notificação do pedido de acesso): em produção as policies de RLS
  # esconderiam a linha do papel de aplicação sem contexto, então a busca
  # cruza pela válvula. Devolve `%Ava{}` ou `nil`, como o `Repo.get/3` que
  # substitui nos sites de sistema.
  defp system_ava(ava_id) do
    {:ok, ava} = Repo.with_system(fn -> {:ok, Repo.get(Ava, ava_id, skip_tekoa_id: true)} end)

    ava
  end

  defp notify_requester(requester_ava_id, message) do
    case system_ava(requester_ava_id) do
      nil -> :ok
      %Ava{} = requester -> notify(requester.public_id, message)
    end
  end

  defp notify(ava_public_id, message) do
    Phoenix.PubSub.broadcast(Taina.PubSub, "maraca:ava:" <> ava_public_id, message)
  end
end
