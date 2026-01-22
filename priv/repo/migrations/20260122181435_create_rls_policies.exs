defmodule Taina.Repo.Migrations.CreateRlsPolicies do
  @moduledoc """
  Implementa políticas de Row-Level Security (RLS) para isolamento de comunidades (Tekoas).

  Seguindo a filosofia do Tainá: isolamento por comunidade é a primeira linha de defesa.
  Todas as queries são automaticamente filtradas pela Tekoa atual através da variável
  de sessão PostgreSQL `app.current_tekoa_id`.

  ## Políticas criadas

  - **Community isolation** - Garante que cada Tekoa só vê seus próprios dados
  - **Automatic filtering** - Mesmo se o código esquecer de filtrar, o banco protege
  - **Defense in depth** - RLS + application layer (Permit) + API boundaries

  ## Variável de contexto

  As políticas dependem de `app.current_tekoa_id` ser definida via:
  ```elixir
  Repo.with_tekoa(tekoa_id, fn -> ... end)
  ```
  """

  use Ecto.Migration

  def up do
    # ============================================================================
    # MARACA SCHEMA - Core auth tables
    # ============================================================================

    # Tekoas: apenas a Tekoa atual é visível
    execute """
    CREATE POLICY tekoa_isolation ON maraca.tekoas
      FOR ALL
      USING (public_id = current_setting('app.current_tekoa_id', true))
    """

    # Avas: apenas Avas da Tekoa atual
    execute """
    CREATE POLICY ava_isolation ON maraca.avas
      FOR ALL
      USING (
        tekoa_id IN (
          SELECT id FROM maraca.tekoas
          WHERE public_id = current_setting('app.current_tekoa_id', true)
        )
      )
    """

    # Permissions: apenas permissões da Tekoa atual
    execute """
    CREATE POLICY permission_isolation ON maraca.permissions
      FOR ALL
      USING (
        tekoa_id IN (
          SELECT id FROM maraca.tekoas
          WHERE public_id = current_setting('app.current_tekoa_id', true)
        )
      )
    """

    # Access Requests: apenas solicitações da Tekoa atual
    execute """
    CREATE POLICY access_request_isolation ON maraca.access_requests
      FOR ALL
      USING (
        tekoa_id IN (
          SELECT id FROM maraca.tekoas
          WHERE public_id = current_setting('app.current_tekoa_id', true)
        )
      )
    """

    # ============================================================================
    # YBIRA SCHEMA - File management
    # ============================================================================

    # Files: apenas arquivos da Tekoa atual
    execute """
    CREATE POLICY file_isolation ON ybira.files
      FOR ALL
      USING (
        tekoa_id IN (
          SELECT id FROM maraca.tekoas
          WHERE public_id = current_setting('app.current_tekoa_id', true)
        )
      )
    """

    # Folders: apenas pastas da Tekoa atual
    execute """
    CREATE POLICY folder_isolation ON ybira.folders
      FOR ALL
      USING (
        tekoa_id IN (
          SELECT id FROM maraca.tekoas
          WHERE public_id = current_setting('app.current_tekoa_id', true)
        )
      )
    """

    # ============================================================================
    # GUARA SCHEMA - Chat/messaging
    # ============================================================================

    # Chats: apenas conversas da Tekoa atual
    execute """
    CREATE POLICY chat_isolation ON guara.chats
      FOR ALL
      USING (
        tekoa_id IN (
          SELECT id FROM maraca.tekoas
          WHERE public_id = current_setting('app.current_tekoa_id', true)
        )
      )
    """

    # Participants: herda isolamento do chat
    execute """
    CREATE POLICY participant_isolation ON guara.participants
      FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM guara.chats c
          WHERE c.id = chat_id
          AND c.tekoa_id IN (
            SELECT id FROM maraca.tekoas
            WHERE public_id = current_setting('app.current_tekoa_id', true)
          )
        )
      )
    """

    # Messages: herda isolamento do chat pai
    execute """
    CREATE POLICY message_isolation ON guara.messages
      FOR ALL
      USING (
        EXISTS (
          SELECT 1 FROM guara.chats c
          WHERE c.id = chat_id
          AND c.tekoa_id IN (
            SELECT id FROM maraca.tekoas
            WHERE public_id = current_setting('app.current_tekoa_id', true)
          )
        )
      )
    """
  end

  def down do
    # Drop all policies in reverse order
    execute "DROP POLICY IF EXISTS message_isolation ON guara.messages"
    execute "DROP POLICY IF EXISTS participant_isolation ON guara.participants"
    execute "DROP POLICY IF EXISTS chat_isolation ON guara.chats"

    execute "DROP POLICY IF EXISTS folder_isolation ON ybira.folders"
    execute "DROP POLICY IF EXISTS file_isolation ON ybira.files"

    execute "DROP POLICY IF EXISTS access_request_isolation ON maraca.access_requests"
    execute "DROP POLICY IF EXISTS permission_isolation ON maraca.permissions"
    execute "DROP POLICY IF EXISTS ava_isolation ON maraca.avas"
    execute "DROP POLICY IF EXISTS tekoa_isolation ON maraca.tekoas"
  end
end
