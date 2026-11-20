defmodule Taina.Repo.Migrations.AddRelativePathToYbiraUploads do
  use Ecto.Migration

  def change do
    alter table(:ybira_uploads) do
      add :relative_path, :text
    end
  end
end
