defmodule Taina.Repo.Migrations.CreateMaracaDeviceTokens do
  @moduledoc """
  O token de dispositivo (RFC_005 secao 4): flat, no estilo das tabelas do
  kernel. O segredo cru nunca entra no banco; so o hash SHA-256.
  """

  use Ecto.Migration

  def change do
    create table(:maraca_device_tokens) do
      add :name, :string, null: false
      add :public_id, :string, null: false
      add :token_hash, :string, null: false
      add :last_used_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :ava_id, references(:maraca_avas, on_delete: :delete_all)
      add :tekoa_id, references(:maraca_tekoas, on_delete: :delete_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:maraca_device_tokens, [:public_id])
    create unique_index(:maraca_device_tokens, [:token_hash])
    create index(:maraca_device_tokens, [:ava_id])
    create index(:maraca_device_tokens, [:tekoa_id])
  end
end
