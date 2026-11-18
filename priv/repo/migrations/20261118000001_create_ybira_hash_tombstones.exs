defmodule Taina.Repo.Migrations.CreateYbiraHashTombstones do
  use Ecto.Migration

  def change do
    create table(:ybira_hash_tombstones) do
      add(:tekoa_id, references(:maraca_tekoas), null: false)
      add(:dono_id, references(:maraca_avas), null: false)
      add(:hash, :string, null: false)
      add(:inserted_at, :utc_datetime, null: false)
    end

    create(unique_index(:ybira_hash_tombstones, [:tekoa_id, :dono_id, :hash]))
  end
end
