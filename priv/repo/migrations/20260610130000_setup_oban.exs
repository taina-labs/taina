defmodule Taina.Repo.Migrations.SetupOban do
  @moduledoc """
  Cria as tabelas do Oban (fila de jobs em background).

  As tabelas vivem no schema `public` (sem RLS) — jobs são infraestrutura, não
  dados de Tekoa. O worker `Taina.Ybira.Workers.PurgeTrash` roda em nível de
  sistema e atravessa todas as Tekoas com `skip_tekoa_id: true`.
  """

  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 14)

  def down, do: Oban.Migrations.down(version: 1)
end
