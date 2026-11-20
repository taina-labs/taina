defmodule Taina.Repo.Migrations.CreateYbiraUploads do
  use Ecto.Migration

  def change do
    create table(:ybira_uploads) do
      add :public_id, :string, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :dono_id, references(:maraca_avas), null: false
      add :folder_rkey, :string
      add :filename, :string, null: false
      add :size, :integer, null: false
      add :staging_key, :string, null: false
      add :state, :string, null: false, default: "queued"
      add :oban_job_id, :integer
      add :file_id, references(:ybira_files)
      add :error_code, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ybira_uploads, [:public_id])
    create unique_index(:ybira_uploads, [:file_id])

    create index(:ybira_uploads, [:tekoa_id, :dono_id, :state, :inserted_at],
             name: :ybira_uploads_owner_state_inserted_at_index
           )

    create index(:ybira_uploads, [:state, :updated_at])
    create index(:ybira_uploads, [:oban_job_id])

    create constraint(:ybira_uploads, :ybira_uploads_size_positive, check: "size > 0")
  end
end
