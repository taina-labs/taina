defmodule Taina.Repo.Migrations.CreateRlsPolicies do
  @moduledoc """
  No Postgres este módulo criava as políticas RLS de isolamento por Tekoa.

  O SQLite nao tem Row-Level Security: o isolamento por comunidade vive na
  camada de aplicação (`Taina.Repo.with_tekoa/2` + guard `prepare_query/3`).
  A migração fica no histórico só para casar a cadeia de versões com a do
  Postgres; nao executa nada.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
