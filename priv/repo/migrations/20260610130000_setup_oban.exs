defmodule Taina.Repo.Migrations.SetupOban do
  @moduledoc """
  Cria as tabelas do Oban (fila de jobs em background).

  Jobs sao infraestrutura, nao dado de Tekoa. O `Oban.Migrations` despacha
  para `Oban.Migrations.SQLite` quando o adaptador do Repo e o SQLite, e a
  cadeia SQLite tem versao unica (tabela criada de uma vez).
  """

  use Ecto.Migration

  def up, do: Oban.Migrations.up(version: 14)

  def down, do: Oban.Migrations.down(version: 1)
end
