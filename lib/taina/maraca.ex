defmodule Taina.Maraca do
  @moduledoc """
  Interface pública para autenticação e autorização do serviço Maraca.

  Este módulo define o contrato para interação de outros serviços (Ybira, Jaci, Guará)
  com funcionalidades de autenticação e autorização.

  ## Filosofia

  - **Usuários são donos de seus dados** - Propriedade explícita
  - **Admins são facilitadores, não deuses** - Devem solicitar acesso
  - **Permissões explícitas** - Nunca implícitas
  - **Auditabilidade total** - Todas as tentativas de acesso registradas

  ## Fluxos de Negócio Suportados

  ### 1. Convite e Registro (Invite-only)

      # Admin convida novo usuário
      {:ok, ava} = invite_user(admin, tekoa, "novo@example.com")
      # Email enviado com token de confirmação

      # Usuário confirma email e define senha
      {:ok, ava} = confirm_email(token, "senha123", "senha123", "username")
      # Conta ativada, confirmed_at definido

  ### 2. Autenticação (Login/Logout)

      # Login com email/password
      {:ok, ava} = sign_in_with_password("user@example.com", "senha123", tekoa)
      # Retorna Ava autenticado

      # Criar sessão
      session_data = create_session(ava)
      # Dados para Phoenix.Session

      # Logout
      :ok = destroy_session(conn)
      # Sessão destruída

  ### 3. Reset de Senha

      # Usuário esqueceu senha
      {:ok, ava} = request_password_reset("user@example.com", tekoa)
      # Email enviado com reset_token (expira em 1h)

      # Usuário define nova senha
      {:ok, ava} = reset_password(token, "novasenha", "novasenha")
      # Senha alterada, token removido

  ### 4. Autorização e Permissões

      # Verificar permissão
      true = authorize?(user, :read, "ybira_file", file.public_id)

      # Dono compartilha arquivo
      {:ok, permission} = grant_permission(owner, recipient, :read, "ybira_file", file_id)

      # Revogar permissão
      :ok = revoke_permission(owner, recipient, :read, "ybira_file", file_id)

  ### 5. Acesso Administrativo (com aprovação)

      # Admin solicita acesso a arquivo de usuário
      {:ok, request} = request_access(admin, owner, "ybira_file", file_id, "Ticket #123")
      # AccessRequest criado, owner notificado

      # Owner aprova
      {:ok, permission} = approve_access_request(owner, request.id)
      # Permission :read criada, admin pode acessar

      # Ou owner nega
      {:ok, request} = deny_access_request(owner, request.id)
      # Request marcado como :denied

  ## Ordem de Resolução de Permissões

  1. **Isolamento de comunidade** (RLS garante tekoa_id)
  2. **Propriedade do recurso** (ava_id == resource.ava_id)
  3. **Permissões explícitas** (tabela maraca.permissions)
  4. **Negação padrão** (se nada acima, acesso negado)
  """
end
