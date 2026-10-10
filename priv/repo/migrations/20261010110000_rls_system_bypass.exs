defmodule Taina.Repo.Migrations.RlsSystemBypass do
  @moduledoc """
  Dá às políticas RLS uma válvula de sistema: `app.bypass_rls`.

  Em produção a aplicação conecta como papel sem superpoderes (`taina_app`,
  ver o oka `deploy/initdb/01-taina-app-role.sh`), então o RLS vale para ela
  de verdade, inclusive nas consultas de sistema (bootstrap de autenticação,
  resolução de sessão, jobs que cruzam Tekoas) que declaram
  `skip_tekoa_id: true` e rodam sem contexto de Tekoa. Sem a válvula, essas
  consultas veriam zero linhas em produção.

  Cada policy ganha um `OR current_setting('app.bypass_rls', true) = 'on'`:
  `Repo.with_system/1` define a variável só dentro da transação de sistema,
  e ela morre com a transação (`set_config(..., true)`). Nenhum caminho
  movido por morador passa pela válvula, então o isolamento por comunidade
  fica intacto para eles.

  O `down` restaura o USING original de cada policy, exatamente o texto com
  que as migrations 20260122181435 e 20261005120000 as criaram.
  """

  use Ecto.Migration

  # A válvula em si. O `true` de current_setting é o missing_ok: unset devolve
  # NULL, e NULL = 'on' é falso na prática -- policy fechada por padrão.
  @bypass "current_setting('app.bypass_rls', true) = 'on'"

  # USING das tabelas que carregam tekoa_id próprio, no texto das policies
  # originais.
  @tekoa_rows """
  tekoa_id IN (
    SELECT id FROM maraca.tekoas
    WHERE public_id = current_setting('app.current_tekoa_id', true)
  )
  """

  # USING das tabelas do Guará que herdam o isolamento pelo chat pai.
  @via_chat """
  EXISTS (
    SELECT 1 FROM guara.chats c
    WHERE c.id = chat_id
    AND c.tekoa_id IN (
      SELECT id FROM maraca.tekoas
      WHERE public_id = current_setting('app.current_tekoa_id', true)
    )
  )
  """

  # {tabela, policy, USING original}, na ordem em que as policies nasceram.
  @policies [
    {"maraca.tekoas", "tekoa_isolation",
     "public_id = current_setting('app.current_tekoa_id', true)"},
    {"maraca.avas", "ava_isolation", @tekoa_rows},
    {"maraca.permissions", "permission_isolation", @tekoa_rows},
    {"maraca.access_requests", "access_request_isolation", @tekoa_rows},
    {"ybira.files", "file_isolation", @tekoa_rows},
    {"ybira.folders", "folder_isolation", @tekoa_rows},
    {"guara.chats", "chat_isolation", @tekoa_rows},
    {"guara.participants", "participant_isolation", @via_chat},
    {"guara.messages", "message_isolation", @via_chat},
    {"maraca.events", "event_isolation", @tekoa_rows}
  ]

  def up do
    for {table, policy, original_using} <- @policies do
      execute "ALTER POLICY #{policy} ON #{table} USING (#{original_using} OR #{@bypass})"
    end
  end

  def down do
    for {table, policy, original_using} <- @policies do
      execute "ALTER POLICY #{policy} ON #{table} USING (#{original_using})"
    end
  end
end
