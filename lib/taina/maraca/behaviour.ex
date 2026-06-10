defmodule Taina.Maraca.Behaviour do
  @moduledoc false

  alias Taina.Maraca.AccessRequest
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Permission
  alias Taina.Maraca.Tekoa
  alias Taina.Scope

  @doc """
  Convida um novo usuário para a Tekoa.

  ## Regras de Negócio

  - Apenas admins podem convidar usuários
  - Gera token único de confirmação de email
  - Email deve ser único dentro da Tekoa
  - Email é enviado com link de confirmação
  - Token expira após 7 dias

  ## Parâmetros

    * `admin_ava` - Ava com role :admin que está convidando
    * `tekoa` - Tekoa à qual o usuário será adicionado
    * `email` - Email do usuário convidado
    * `opts` - Opções adicionais (role, etc.)

  ## Retorno

    * `{:ok, %Ava{}}` - Convite criado, email enviado
    * `{:error, :not_admin}` - Apenas admins podem convidar
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> invite_user(admin, tekoa, "novo@example.com")
      {:ok, %Ava{email: "novo@example.com", confirmed_at: nil}}

      iex> invite_user(member, tekoa, "outro@example.com")
      {:error, :not_admin}
  """
  @callback invite_user(Ava.t(), Tekoa.t(), String.t(), keyword()) ::
              {:ok, Ava.t()} | {:error, :not_admin | Ecto.Changeset.t()}

  @doc """
  Confirma email do usuário e ativa a conta.

  ## Regras de Negócio

  - Token deve ser válido e não expirado (< 7 dias)
  - Senha deve ter no mínimo 8 caracteres
  - Senha e confirmação devem coincidir
  - Username deve ser único dentro da Tekoa (3-50 caracteres)
  - Define confirmed_at e remove token

  ## Parâmetros

    * `token` - Token recebido por email
    * `password` - Senha do usuário
    * `password_confirmation` - Confirmação da senha
    * `username` - Nome de usuário escolhido

  ## Retorno

    * `{:ok, %Ava{}}` - Conta confirmada e ativada
    * `{:error, :invalid_token}` - Token inválido ou expirado
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> confirm_email(token, "senha123", "senha123", "maria")
      {:ok, %Ava{confirmed_at: ~U[2026-01-22 20:00:00Z], username: "maria"}}

      iex> confirm_email("invalid", "senha", "senha", "user")
      {:error, :invalid_token}
  """
  @callback confirm_email(String.t(), String.t(), String.t(), String.t()) ::
              {:ok, Ava.t()} | {:error, :invalid_token | Ecto.Changeset.t()}

  @doc """
  Autentica usuário com email e senha.

  ## Regras de Negócio

  - Email e senha devem estar corretos
  - Email deve estar confirmado (confirmed_at não nulo)
  - Usa bcrypt para verificar senha
  - Retorna Ava completo se autenticado

  ## Parâmetros

    * `email` - Email do usuário
    * `password` - Senha do usuário
    * `tekoa` - Tekoa onde o usuário está registrado

  ## Retorno

    * `{:ok, %Ava{}}` - Autenticado com sucesso
    * `{:error, :invalid_credentials}` - Email ou senha incorretos
    * `{:error, :email_not_confirmed}` - Email ainda não confirmado

  ## Exemplos

      iex> authenticate("user@example.com", "senha123", tekoa)
      {:ok, %Ava{email: "user@example.com"}}

      iex> authenticate("user@example.com", "senhaerrada", tekoa)
      {:error, :invalid_credentials}
  """
  @callback authenticate(String.t(), String.t(), Tekoa.t()) ::
              {:ok, Ava.t()} | {:error, :invalid_credentials | :email_not_confirmed}

  @doc """
  Cria dados de sessão para usuário autenticado.

  ## Regras de Negócio

  - Retorna mapa com dados para armazenar em Phoenix.Session
  - Inclui: ava_id, tekoa_id, role
  - Usado após autenticação bem-sucedida

  ## Parâmetros

    * `ava` - Ava autenticado

  ## Retorno

    * Mapa com dados da sessão

  ## Exemplos

      iex> create_session(ava)
      %{ava_id: "ava_123", tekoa_id: "tekoa_456", role: :member}
  """
  @callback create_session(Ava.t()) :: map()

  @doc """
  Destroi sessão do usuário (logout).

  ## Regras de Negócio

  - Remove dados da sessão Phoenix (drop completo, previne fixation)
  - Retorna a conexão atualizada (Plug.Conn é imutável)

  ## Parâmetros

    * `conn` - Conexão com sessão

  ## Retorno

    * `%Plug.Conn{}` - Conexão com sessão descartada

  ## Exemplos

      iex> destroy_session(conn)
      %Plug.Conn{}
  """
  @callback destroy_session(Plug.Conn.t()) :: Plug.Conn.t()

  @doc """
  Bootstrap de primeira inicialização: cria a Tekoa única e o admin inicial.

  ## Regras de Negócio

  - Só funciona em instância vazia — se já existe Tekoa, retorna
    `{:error, :already_bootstrapped}` (reforçado pelo índice único
    `single_tekoa_enforcement` no banco; ver RFC 002, D2)
  - Admin é criado já confirmado (`confirmed_at`), com senha definida e
    `role: :admin`
  - Tekoa + admin na mesma transação

  ## Parâmetros

    * `tekoa_attrs` - `%{name: ..., storage_quota_bytes: ...}`
    * `admin_attrs` - `%{username: ..., email: ..., password: ..., password_confirmation: ...}`

  ## Retorno

    * `{:ok, %{tekoa: %Tekoa{}, ava: %Ava{}}}` - Instância inicializada
    * `{:error, :already_bootstrapped}` - Já existe Tekoa
    * `{:error, %Ecto.Changeset{}}` - Validação falhou
  """
  @callback bootstrap(map(), map()) ::
              {:ok, %{tekoa: Tekoa.t(), ava: Ava.t()}}
              | {:error, :already_bootstrapped | Ecto.Changeset.t()}

  @doc """
  Obtém Ava da sessão atual.

  ## Regras de Negócio

  - Extrai ava_id da sessão
  - Carrega Ava do banco com preload de tekoa
  - Usado em controllers e LiveViews

  ## Parâmetros

    * `conn_or_socket` - Conexão ou socket com sessão

  ## Retorno

    * `{:ok, %Ava{}}` - Usuário autenticado
    * `{:error, :not_authenticated}` - Sem sessão válida

  ## Exemplos

      iex> get_session_user(conn)
      {:ok, %Ava{email: "user@example.com"}}
  """
  @callback get_session_user(Plug.Conn.t()) ::
              {:ok, Ava.t()} | {:error, :not_authenticated}

  @doc """
  Atualiza a cota de armazenamento da Tekoa do scope.

  ## Regras de Negócio

  - Apenas admins podem alterar a cota (`scope.ava.role == :admin`)
  - `quota_bytes` deve ser maior que zero
  - Demais (membros) recebem `{:error, :unauthorized}`

  ## Parâmetros

    * `scope` - `Taina.Scope` de quem está agindo + a Tekoa
    * `quota_bytes` - novo limite de armazenamento, em bytes

  ## Retorno

    * `{:ok, %Tekoa{}}` - cota atualizada
    * `{:error, :unauthorized}` - quem pediu não é admin
    * `{:error, %Ecto.Changeset{}}` - validação falhou (ex.: cota <= 0)

  ## Exemplos

      iex> update_tekoa_quota(admin_scope, 10 * 1024 * 1024 * 1024)
      {:ok, %Tekoa{storage_quota_bytes: 10737418240}}

      iex> update_tekoa_quota(member_scope, 1024)
      {:error, :unauthorized}
  """
  @callback update_tekoa_quota(Scope.t(), pos_integer()) ::
              {:ok, Tekoa.t()} | {:error, :unauthorized | Ecto.Changeset.t()}

  # ============================================================================
  # AUTENTICAÇÃO - Reset de Senha
  # ============================================================================

  @doc """
  Solicita reset de senha.

  ## Regras de Negócio

  - Gera reset_token único
  - Token expira após 1 hora
  - Email é enviado com link de reset
  - Funciona mesmo se email não existir (segurança)

  ## Parâmetros

    * `email` - Email do usuário
    * `tekoa` - Tekoa onde o usuário está registrado

  ## Retorno

    * `{:ok, %Ava{}}` - Token gerado, email enviado
    * `{:ok, :email_sent}` - Email não existe, mas resposta igual (segurança)

  ## Exemplos

      iex> request_password_reset("user@example.com", tekoa)
      {:ok, %Ava{reset_token: "abc...", reset_token_sent_at: ~U[...]}}
  """
  @callback request_password_reset(String.t(), Tekoa.t()) :: {:ok, Ava.t() | :email_sent}

  @doc """
  Completa reset de senha.

  ## Regras de Negócio

  - Token deve ser válido e não expirado (< 1 hora)
  - Nova senha deve ter no mínimo 8 caracteres
  - Senha e confirmação devem coincidir
  - Remove reset_token após sucesso

  ## Parâmetros

    * `reset_token` - Token recebido por email
    * `new_password` - Nova senha
    * `password_confirmation` - Confirmação da nova senha

  ## Retorno

    * `{:ok, %Ava{}}` - Senha alterada com sucesso
    * `{:error, :invalid_token}` - Token inválido ou expirado
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> reset_password(token, "novasenha123", "novasenha123")
      {:ok, %Ava{reset_token: nil}}

      iex> reset_password("invalid", "senha", "senha")
      {:error, :invalid_token}
  """
  @callback reset_password(String.t(), String.t(), String.t()) ::
              {:ok, Ava.t()} | {:error, :invalid_token | Ecto.Changeset.t()}

  @doc """
  Verifica se Ava tem permissão para ação em recurso.

  ## Ordem de Resolução

  1. **RLS** - Comunidade isolada (tekoa_id deve corresponder)
  2. **Propriedade** - Se ava_id == resource.ava_id, acesso automático
  3. **Permissão explícita** - Verifica tabela maraca.permissions
  4. **Negação padrão** - Se nada acima, retorna false

  ## Regras de Negócio

  - Admins NÃO têm acesso automático (devem solicitar via AccessRequest)
  - Dono do recurso sempre tem todas as permissões
  - Permissões explícitas são verificadas na tabela permissions

  ## Parâmetros

    * `ava` - Ava que está tentando acessar
    * `action` - Ação desejada (:read, :write, :delete, :share)
    * `resource_type` - Tipo do recurso ("ybira_file", "guara_chat", etc.)
    * `resource_id` - public_id do recurso

  ## Retorno

    * `true` - Autorizado
    * `false` - Não autorizado

  ## Exemplos

      iex> authorize?(file_owner, :read, "ybira_file", file.public_id)
      true

      iex> authorize?(other_user, :read, "ybira_file", file.public_id)
      false

      iex> authorize?(admin, :read, "ybira_file", user_file.public_id)
      false  # Admin precisa solicitar acesso
  """
  @callback authorize?(Ava.t(), atom(), String.t(), String.t()) :: boolean()

  @doc """
  Versão que levanta exceção se não autorizado.

  ## Parâmetros

    * `ava` - Ava que está tentando acessar
    * `action` - Ação desejada
    * `resource_type` - Tipo do recurso
    * `resource_id` - ID do recurso

  ## Retorno

    * `:ok` - Autorizado
    * Levanta `Taina.Maraca.UnauthorizedError`

  ## Exemplos

      iex> authorize!(owner, :read, "ybira_file", file.public_id)
      :ok

      iex> authorize!(other_user, :delete, "ybira_file", file.public_id)
      ** (Taina.Maraca.UnauthorizedError) não autorizado
  """
  @callback authorize!(Ava.t(), atom(), String.t(), String.t()) :: :ok

  @doc """
  Concede permissão de granter a recipient.

  ## Regras de Negócio

  - **APENAS o dono do recurso pode conceder permissões**
  - Não é possível conceder :share (delegação desabilitada)
  - Permissão é única por (ava_id, resource_type, resource_id, action)
  - Grava granted_by_id para auditoria

  ## Parâmetros

    * `granter_ava` - Ava que está concedendo (deve ser dono)
    * `recipient_ava` - Ava que receberá a permissão
    * `action` - Ação permitida (:read, :write, :delete)
    * `resource_type` - Tipo do recurso
    * `resource_id` - ID do recurso

  ## Retorno

    * `{:ok, %Permission{}}` - Permissão concedida
    * `{:error, :not_owner}` - Granter não é dono do recurso
    * `{:error, :invalid_action}` - Tentou conceder :share
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> grant_permission(owner, user_b, :read, "ybira_file", file.public_id)
      {:ok, %Permission{action: :read}}

      iex> grant_permission(non_owner, user_b, :read, "ybira_file", file.public_id)
      {:error, :not_owner}

      iex> grant_permission(owner, user_b, :share, "ybira_file", file.public_id)
      {:error, :invalid_action}
  """
  @callback grant_permission(Ava.t(), Ava.t(), atom(), String.t(), String.t()) ::
              {:ok, Permission.t()} | {:error, :not_owner | :invalid_action | Ecto.Changeset.t()}

  @doc """
  Revoga permissão de recipient.

  ## Regras de Negócio

  - Apenas dono do recurso ou quem concedeu pode revogar
  - Remove entrada da tabela permissions

  ## Parâmetros

    * `revoker_ava` - Ava que está revogando
    * `recipient_ava` - Ava que perderá a permissão
    * `action` - Ação a ser revogada
    * `resource_type` - Tipo do recurso
    * `resource_id` - ID do recurso

  ## Retorno

    * `:ok` - Permissão revogada
    * `{:error, :not_authorized}` - Não pode revogar
    * `{:error, :not_found}` - Permissão não existe

  ## Exemplos

      iex> revoke_permission(owner, user_b, :read, "ybira_file", file.public_id)
      :ok

      iex> revoke_permission(random_user, user_b, :read, "ybira_file", file.public_id)
      {:error, :not_authorized}
  """
  @callback revoke_permission(Ava.t(), Ava.t(), atom(), String.t(), String.t()) ::
              :ok | {:error, :not_authorized | :not_found}

  @doc """
  Lista todas as permissões de um recurso.

  ## Parâmetros

    * `resource_type` - Tipo do recurso
    * `resource_id` - ID do recurso

  ## Retorno

    * Lista de `%Permission{}` com preload de ava e granted_by

  ## Exemplos

      iex> list_permissions("ybira_file", file.public_id)
      [%Permission{ava: %Ava{}, action: :read}]
  """
  @callback list_permissions(String.t(), String.t()) :: [Permission.t()]

  @doc """
  Admin solicita acesso a recurso de usuário.

  ## Regras de Negócio

  - Apenas admins podem solicitar acesso
  - Cria AccessRequest com status :pending (não pode ser alterado na criação)
  - Owner é notificado via PubSub
  - Justificativa (reason) é obrigatória (max 250 chars)
  - Não pode solicitar se já tem permissão

  ## Implementação

  Use `AccessRequest.create_changeset/2` para criar a solicitação,
  garantindo que o status seja sempre :pending.

  ## Parâmetros

    * `admin_ava` - Admin solicitando acesso
    * `owner_ava` - Dono do recurso
    * `resource_type` - Tipo do recurso
    * `resource_id` - ID do recurso
    * `reason` - Justificativa (ex: "Ticket de suporte #123")

  ## Retorno

    * `{:ok, %AccessRequest{}}` - Solicitação criada
    * `{:error, :not_admin}` - Apenas admins podem solicitar
    * `{:error, :already_has_access}` - Admin já tem permissão
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> request_access(admin, owner, "ybira_file", file.public_id, "Ticket #123")
      {:ok, %AccessRequest{status: :pending}}

      iex> request_access(member, owner, "ybira_file", file.public_id, "Motivo")
      {:error, :not_admin}
  """
  @callback request_access(Ava.t(), Ava.t(), String.t(), String.t(), String.t()) ::
              {:ok, AccessRequest.t()}
              | {:error, :not_admin | :already_has_access | Ecto.Changeset.t()}

  @doc """
  Owner aprova solicitação de acesso.

  ## Regras de Negócio

  - Apenas owner pode aprovar
  - AccessRequest deve estar :pending
  - Cria Permission com action :read
  - Atualiza status para :approved
  - Admin é notificado via PubSub

  ## Parâmetros

    * `owner_ava` - Dono do recurso
    * `access_request_id` - ID da solicitação

  ## Retorno

    * `{:ok, %Permission{}}` - Acesso concedido
    * `{:error, :not_owner}` - Apenas owner pode aprovar
    * `{:error, :invalid_status}` - Request não está pending
    * `{:error, :not_found}` - Request não encontrado

  ## Exemplos

      iex> approve_access_request(owner, request.id)
      {:ok, %Permission{action: :read}}
  """
  @callback approve_access_request(Ava.t(), integer()) ::
              {:ok, Permission.t()} | {:error, :not_owner | :invalid_status | :not_found}

  @doc """
  Owner nega solicitação de acesso.

  ## Regras de Negócio

  - Apenas owner pode negar
  - AccessRequest deve estar :pending
  - Atualiza status para :denied
  - Admin é notificado via PubSub
  - Request permanece no banco para auditoria

  ## Parâmetros

    * `owner_ava` - Dono do recurso
    * `access_request_id` - ID da solicitação

  ## Retorno

    * `{:ok, %AccessRequest{}}` - Acesso negado
    * `{:error, :not_owner}` - Apenas owner pode negar
    * `{:error, :invalid_status}` - Request não está pending
    * `{:error, :not_found}` - Request não encontrado

  ## Exemplos

      iex> deny_access_request(owner, request.id)
      {:ok, %AccessRequest{status: :denied}}
  """
  @callback deny_access_request(Ava.t(), integer()) ::
              {:ok, AccessRequest.t()} | {:error, :not_owner | :invalid_status | :not_found}

  @doc """
  Lista solicitações de acesso pendentes para um owner.

  ## Parâmetros

    * `owner_ava` - Dono dos recursos

  ## Retorno

    * Lista de `%AccessRequest{}` com status :pending

  ## Exemplos

      iex> list_access_requests(owner)
      [%AccessRequest{status: :pending, reason: "Ticket #123"}]
  """
  @callback list_access_requests(Ava.t()) :: [AccessRequest.t()]

  @doc """
  Verifica se Ava é admin na sua Tekoa.

  ## Parâmetros

    * `ava` - Ava a verificar

  ## Retorno

    * `true` - É admin
    * `false` - Não é admin

  ## Exemplos

      iex> admin?(admin_ava)
      true

      iex> admin?(member_ava)
      false
  """
  @callback admin?(Ava.t()) :: boolean()

  @doc """
  Verifica se email do Ava foi confirmado.

  ## Parâmetros

    * `ava` - Ava a verificar

  ## Retorno

    * `true` - Email confirmado (confirmed_at não é nil)
    * `false` - Email não confirmado

  ## Exemplos

      iex> email_confirmed?(confirmed_ava)
      true

      iex> email_confirmed?(invited_ava)
      false
  """
  @callback email_confirmed?(Ava.t()) :: boolean()
end
