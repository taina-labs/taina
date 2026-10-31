defmodule DropAssembleiaTables do
  @moduledoc """
  A assembleia sai do MVP (RFC_003: a trilha de governanca coletiva volta por
  RFC propria, depois do produto). Sem codigo que use as tabelas, elas saem;
  o `down` recria as duas exatamente como `20261012000001_ypy_kernel_tables`
  as criou.
  """

  use Ecto.Migration

  def up do
    drop table(:assembleia_votos)
    drop table(:assembleia_propostas)
  end

  def down do
    create table(:assembleia_propostas) do
      add :tipo, :string, null: false
      add :payload, :map, default: "{}"
      add :status, :string, null: false, default: "aberta"
      add :fecha_em, :utc_datetime, null: false
      add :executado_em, :utc_datetime
      add :public_id, :string, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :autor_id, references(:maraca_avas), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assembleia_propostas, [:public_id])
    create index(:assembleia_propostas, [:tekoa_id, :status])

    create table(:assembleia_votos) do
      add :escolha, :string, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :proposta_id, references(:assembleia_propostas), null: false
      add :ava_id, references(:maraca_avas), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:assembleia_votos, [:proposta_id, :ava_id])
    create index(:assembleia_votos, [:tekoa_id])
  end
end
