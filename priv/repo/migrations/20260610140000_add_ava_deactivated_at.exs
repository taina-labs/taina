defmodule Taina.Repo.Migrations.AddAvaDeactivatedAt do
  @moduledoc """
  Desativação de conta (RFC 002, Fase 1 — "Admin: desativar conta"). Soft state:
  `deactivated_at` preenchido bloqueia login (`Maraca.authenticate/3`); a conta e
  seus dados permanecem. NULL = ativa.
  """

  use Ecto.Migration

  def change do
    alter table(:avas, prefix: "maraca") do
      add :deactivated_at, :utc_datetime_usec
    end
  end
end
