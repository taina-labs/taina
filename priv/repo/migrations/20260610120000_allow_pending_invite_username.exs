defmodule Taina.Repo.Migrations.AllowPendingInviteUsername do
  @moduledoc """
  No fluxo invite-only o Ava nasce só com email + token; o username é
  escolhido na confirmação (`Maraca.confirm_email/4`). A coluna não pode
  ser NOT NULL.

  Porta SQLite: o SQLite nao tem `ALTER COLUMN DROP NOT NULL` (so recreacao
  completa da tabela). Para nao recriar `avas` em uma migracao, o estado
  final fica compactado na criacao da tabela (`username` nullable desde
  20251007182041) e esta migracao vira no-op.
  """

  use Ecto.Migration

  def up, do: :ok

  def down, do: :ok
end
