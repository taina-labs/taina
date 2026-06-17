defmodule Taina.Maraca.Behaviour do
  @moduledoc false

  alias Taina.Maraca.AccessRequest
  alias Taina.Maraca.Ava
  alias Taina.Maraca.Permission
  alias Taina.Maraca.Tekoa
  alias Taina.Scope

  @doc """
  Convida uma pessoa para a Tekoa (por link/QR, sem e-mail).

  ## Regras de Negócio

  - Apenas zeladores podem convidar
  - Cria um Ava pendente com token de convite; nome e senha vêm no aceite
  - O token cru volta em `invite_token` (campo virtual) para montar o link/QR
  - Papel padrão é `:morador`
  - Token expira após 7 dias

  ## Parâmetros

    * `zelador_ava` - Ava com role :zelador que está convidando
    * `tekoa` - Tekoa à qual a pessoa será adicionada
    * `opts` - Opções (`:role`, padrão `:morador`)

  ## Retorno

    * `{:ok, %Ava{}}` - Convite criado (token cru em `invite_token`)
    * `{:error, :not_zelador}` - Apenas zeladores podem convidar
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> invite_user(zelador, tekoa, role: :morador)
      {:ok, %Ava{invite_token: "abc...", activated_at: nil}}

      iex> invite_user(morador, tekoa, [])
      {:error, :not_zelador}
  """
  @callback invite_user(Ava.t(), Tekoa.t(), keyword()) ::
              {:ok, Ava.t()} | {:error, :not_zelador | Ecto.Changeset.t()}

  @doc """
  Aceita o convite e cria a conta (a pessoa escolhe nome e senha).

  ## Regras de Negócio

  - Token de convite deve ser válido e não expirado (< 7 dias)
  - `username` é obrigatório, handle único na Tekoa (3-50 caracteres)
  - `display_name` é opcional
  - Senha mínima de 8 caracteres, igual à confirmação
  - Define `activated_at` e queima o token de convite

  ## Parâmetros

    * `token` - Token de convite (veio no link/QR)
    * `attrs` - Mapa com `username`, `password`, `password_confirmation` e,
      opcionalmente, `display_name` (chaves string ou atom)

  ## Retorno

    * `{:ok, %Ava{}}` - Conta criada e ativa
    * `{:error, :invalid_token}` - Token inválido ou expirado
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> accept_invite(token, %{"username" => "maria", "password" => "senha1234", "password_confirmation" => "senha1234"})
      {:ok, %Ava{activated_at: ~U[2026-06-16 20:00:00Z], username: "maria"}}

      iex> accept_invite("invalid", %{})
      {:error, :invalid_token}
  """
  @callback accept_invite(String.t(), map()) ::
              {:ok, Ava.t()} | {:error, :invalid_token | Ecto.Changeset.t()}

  @doc """
  Autentica usuário com nome de usuário e senha.

  ## Regras de Negócio

  - Nome de usuário e senha devem estar corretos
  - Conta sem senha definida (convite ainda não aceito) não autentica
  - Usa bcrypt para verificar senha
  - Retorna Ava completo se autenticado

  ## Parâmetros

    * `username` - Nome de usuário (handle único na Tekoa)
    * `password` - Senha do usuário
    * `tekoa` - Tekoa onde o usuário está registrado

  ## Retorno

    * `{:ok, %Ava{}}` - Autenticado com sucesso
    * `{:error, :invalid_credentials}` - Nome de usuário ou senha incorretos

  ## Exemplos

      iex> authenticate("maria", "senha123", tekoa)
      {:ok, %Ava{username: "maria"}}

      iex> authenticate("maria", "senhaerrada", tekoa)
      {:error, :invalid_credentials}
  """
  @callback authenticate(String.t(), String.t(), Tekoa.t()) ::
              {:ok, Ava.t()} | {:error, :invalid_credentials}

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
      %{ava_id: "ava_123", tekoa_id: "tekoa_456", role: :morador}
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
  Bootstrap de primeira inicialização: cria a Tekoa única e o zelador inicial.

  ## Regras de Negócio

  - Só funciona em instância vazia, se já existe Tekoa, retorna
    `{:error, :already_bootstrapped}` (reforçado pelo índice único
    `single_tekoa_enforcement` no banco; ver RFC 002, D2)
  - O zelador inicial é criado já ativo (`activated_at`), com senha e
    `role: :zelador`
  - Tekoa + zelador na mesma transação

  ## Parâmetros

    * `tekoa_attrs` - `%{name: ..., storage_quota_bytes: ...}`
    * `zelador_attrs` - `%{username: ..., display_name: ..., password: ..., password_confirmation: ...}`

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

    * `conn_or_session` - a `Plug.Conn` (controllers/plugs) **ou** o mapa de
      sessão de chaves string que o `on_mount` do LiveView recebe

  ## Retorno

    * `{:ok, %Ava{}}` - Usuário autenticado (com a Tekoa pré-carregada)
    * `{:error, :not_authenticated}` - Sem sessão válida

  ## Exemplos

      iex> get_session_user(conn)
      {:ok, %Ava{username: "maria"}}

      iex> get_session_user(%{"ava_id" => "V1StGXR8_Z5j"})
      {:ok, %Ava{}}
  """
  @callback get_session_user(Plug.Conn.t() | map()) ::
              {:ok, Ava.t()} | {:error, :not_authenticated}

  @doc """
  Atualiza a cota de armazenamento da Tekoa do scope.

  ## Regras de Negócio

  - Apenas zeladores podem alterar a cota (`scope.ava.role == :zelador`)
  - `quota_bytes` deve ser maior que zero
  - Moradores recebem `{:error, :unauthorized}`

  ## Parâmetros

    * `scope` - `Taina.Scope` de quem está agindo + a Tekoa
    * `quota_bytes` - novo limite de armazenamento, em bytes

  ## Retorno

    * `{:ok, %Tekoa{}}` - cota atualizada
    * `{:error, :unauthorized}` - quem pediu não é zelador
    * `{:error, %Ecto.Changeset{}}` - validação falhou (ex.: cota <= 0)

  ## Exemplos

      iex> update_tekoa_quota(zelador_scope, 10 * 1024 * 1024 * 1024)
      {:ok, %Tekoa{storage_quota_bytes: 10737418240}}

      iex> update_tekoa_quota(morador_scope, 1024)
      {:error, :unauthorized}
  """
  @callback update_tekoa_quota(Scope.t(), pos_integer()) ::
              {:ok, Tekoa.t()} | {:error, :unauthorized | Ecto.Changeset.t()}

  # ============================================================================
  # AUTENTICAÇÃO - Reset de Senha
  # ============================================================================

  @doc """
  Zelador gera um link de redefinição de senha para uma pessoa.

  Sem e-mail, a recuperação é mediada: o zelador gera o token e entrega o link
  pelo mesmo canal dos convites (RFC_003 seção 4). É cuidado-da-máquina, não dá
  ao zelador a senha nem os dados de ninguém.

  ## Regras de Negócio

  - Apenas zeladores podem gerar o link
  - Gera `reset_token` único; expira após 1 hora
  - O token cru volta em `reset_token` (campo virtual) para montar o link

  ## Parâmetros

    * `scope` - `Taina.Scope` de quem age (deve ser zelador)
    * `member` - o Ava que recuperará o acesso

  ## Retorno

    * `{:ok, %Ava{}}` - Token gerado (cru em `reset_token`)
    * `{:error, :unauthorized}` - Quem pediu não é zelador
    * `{:error, :not_found}` - Pessoa não encontrada na Tekoa

  ## Exemplos

      iex> mint_reset_link(zelador_scope, member)
      {:ok, %Ava{reset_token: "abc...", reset_token_sent_at: ~U[...]}}
  """
  @callback mint_reset_link(Scope.t(), Ava.t()) ::
              {:ok, Ava.t()} | {:error, :unauthorized | :not_found}

  @doc """
  Completa reset de senha.

  ## Regras de Negócio

  - Token deve ser válido e não expirado (< 1 hora)
  - Nova senha deve ter no mínimo 8 caracteres
  - Senha e confirmação devem coincidir
  - Remove reset_token após sucesso

  ## Parâmetros

    * `reset_token` - Token recebido pelo link de redefinição
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

  - Zeladores NÃO têm acesso automático (devem solicitar via AccessRequest)
  - Dono do recurso sempre tem todas as permissões
  - Permissões explícitas são verificadas na tabela permissions

  ## Parâmetros

    * `ava` - Ava que está tentando acessar
    * `action` - Ação desejada (:read, :write, :delete)
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

      iex> authorize?(zelador, :read, "ybira_file", user_file.public_id)
      false  # Zelador precisa solicitar acesso
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
  - Só ações concedíveis são aceitas (:read, :write, :delete)
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
    * `{:error, :invalid_action}` - Ação fora de (:read, :write, :delete)
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> grant_permission(owner, user_b, :read, "ybira_file", file.public_id)
      {:ok, %Permission{action: :read}}

      iex> grant_permission(non_owner, user_b, :read, "ybira_file", file.public_id)
      {:error, :not_owner}

      iex> grant_permission(owner, user_b, :manage, "ybira_file", file.public_id)
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
  Morador pede acesso ao recurso de outra pessoa (RFC_003, D4).

  ## Regras de Negócio

  - Qualquer morador pode pedir acesso (inclusive o zelador, que não tem atalho
    para a casa de ninguém)
  - Não se pede acesso ao próprio recurso
  - Cria AccessRequest com status :pending (não pode ser alterado na criação)
  - Owner é notificado via PubSub
  - Justificativa (reason) é obrigatória (max 250 chars)
  - Não pode pedir se já tem permissão

  ## Implementação

  Use `AccessRequest.create_changeset/2` para criar a solicitação,
  garantindo que o status seja sempre :pending.

  ## Parâmetros

    * `requester_ava` - Pessoa pedindo acesso
    * `owner_ava` - Dono do recurso
    * `resource_type` - Tipo do recurso
    * `resource_id` - ID do recurso
    * `reason` - Justificativa (ex: "Ticket de suporte #123")

  ## Retorno

    * `{:ok, %AccessRequest{}}` - Solicitação criada
    * `{:error, :cross_tekoa_owner}` - Dono e quem pede são de comunidades diferentes
    * `{:error, :cannot_request_own}` - Não se pede acesso ao próprio recurso
    * `{:error, :already_has_access}` - Quem pede já tem permissão
    * `{:error, %Ecto.Changeset{}}` - Validação falhou

  ## Exemplos

      iex> request_access(morador, owner, "ybira_file", file.public_id, "Ticket #123")
      {:ok, %AccessRequest{status: :pending}}

      iex> request_access(owner, owner, "ybira_file", file.public_id, "Motivo")
      {:error, :cannot_request_own}
  """
  @callback request_access(Ava.t(), Ava.t(), String.t(), String.t(), String.t()) ::
              {:ok, AccessRequest.t()}
              | {:error, :cross_tekoa_owner | :cannot_request_own | :already_has_access | Ecto.Changeset.t()}

  @doc """
  Owner aprova solicitação de acesso.

  ## Regras de Negócio

  - Apenas owner pode aprovar
  - AccessRequest deve estar :pending
  - Cria Permission com action :read
  - Atualiza status para :approved
  - Zelador é notificado via PubSub

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
  - Zelador é notificado via PubSub
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
  Lista os pedidos de acesso pendentes feitos por uma pessoa (RFC_003, D4).

  Complementa `list_access_requests/1` (caixa de entrada do dono): aqui é a visão
  de quem pede, os pedidos que a pessoa fez e ainda aguardam decisão.

  ## Parâmetros

    * `requester_ava` - Pessoa que fez os pedidos

  ## Retorno

    * Lista de `%AccessRequest{}` com status :pending (com `:owner` pré-carregado)

  ## Exemplos

      iex> list_my_requests(requester)
      [%AccessRequest{status: :pending, reason: "Ticket #123"}]
  """
  @callback list_my_requests(Ava.t()) :: [AccessRequest.t()]

  @doc """
  Verifica se o Ava é zelador(a) na sua Tekoa.
  """
  @callback zelador?(Ava.t()) :: boolean()

  @doc """
  Verifica se o Ava é morador(a) na sua Tekoa.
  """
  @callback morador?(Ava.t()) :: boolean()

  @doc """
  Verifica se a conta está ativa (a pessoa já aceitou o convite).

  ## Retorno

    * `true` - `activated_at` definido (convite aceito)
    * `false` - Convite ainda pendente
  """
  @callback activated?(Ava.t()) :: boolean()

  @doc """
  Verifica se a instância já passou pelo setup (existe a Tekoa única).

  Consulta de sistema (`skip_tekoa_id: true`): roda antes de existir sessão,
  no redirecionamento para o wizard de primeiro boot.

  ## Retorno

    * `true` - Setup concluído, instância pronta
    * `false` - Instância virgem, redirecionar para `/setup`
  """
  @callback bootstrapped?() :: boolean()

  @doc """
  Obtém a Tekoa única da instância (RFC 002, D2, modo single-tekoa).

  Consulta de sistema (`skip_tekoa_id: true`): usada no login, antes de haver
  scope, `authenticate/3` precisa da Tekoa e o usuário ainda não provou quem é.

  ## Retorno

    * `{:ok, %Tekoa{}}` - A Tekoa da instância
    * `{:error, :not_bootstrapped}` - Setup ainda não rodou
  """
  @callback get_tekoa() :: {:ok, Tekoa.t()} | {:error, :not_bootstrapped}

  @doc """
  Lista os membros da Tekoa do scope, ordenados por papel (zeladores primeiro)
  e data de entrada.

  ## Regras de Negócio

  - Inclui contas ainda não confirmadas (convites pendentes) e desativadas,
    a tela de membros mostra o estado de cada uma
  - Isolamento via RLS (scope-first)

  ## Retorno

    * `{:ok, [%Ava{}]}` - Membros da comunidade
  """
  @callback list_members(Scope.t()) :: {:ok, [Ava.t()]}

  @doc """
  Conta os membros da Tekoa do scope (card "Membros" da home).

  ## Retorno

    * `{:ok, count}` - Total de membros
  """
  @callback count_members(Scope.t()) :: {:ok, non_neg_integer()}
end
