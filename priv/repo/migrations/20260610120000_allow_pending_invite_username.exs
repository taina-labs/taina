defmodule Taina.Repo.Migrations.AllowPendingInviteUsername do
  @moduledoc """
  No fluxo invite-only o Ava nasce só com email + token; o username é
  escolhido na confirmação (`Maraca.confirm_email/4`). A coluna não pode
  ser NOT NULL.
  """

  use Ecto.Migration

  def change do
    execute "ALTER TABLE maraca.avas ALTER COLUMN username DROP NOT NULL",
            "ALTER TABLE maraca.avas ALTER COLUMN username SET NOT NULL"
  end
end
