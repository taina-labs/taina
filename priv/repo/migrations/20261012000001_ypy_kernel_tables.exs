defmodule YpyKernelTables do
  @moduledoc """
  As tabelas do kernel (RFC_006 secao 7): flat, sem schema de Postgres, sem
  RLS, sem operador de JSON, portaveis para SQLite. Toda tabela com escopo de
  Tekoa carrega `tekoa_id`, e toda query do kernel filtra `tekoa_id`
  explicitamente.
  """

  use Ecto.Migration

  def change do
    create table(:maraca_tekoas) do
      add :name, :string, null: false
      add :domain, :string, null: false
      add :public_id, :string, null: false
      add :settings, :map, default: "{}"
      add :storage_quota_bytes, :integer
      add :storage_used_bytes, :integer, default: 0, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:maraca_tekoas, [:domain])
    create unique_index(:maraca_tekoas, [:public_id])

    create table(:maraca_avas) do
      add :username, :string
      add :display_name, :string
      add :papel, :string, null: false, default: "morador"
      add :public_id, :string, null: false
      add :password_hash, :string
      add :activated_at, :utc_datetime
      add :invite_token_hash, :string
      add :invite_sent_at, :utc_datetime
      add :reset_token_hash, :string
      add :reset_sent_at, :utc_datetime
      add :invited_at, :utc_datetime
      add :deactivated_at, :utc_datetime
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :invited_by_id, references(:maraca_avas)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:maraca_avas, [:tekoa_id, :username])
    create unique_index(:maraca_avas, [:public_id])

    create unique_index(:maraca_avas, [:invite_token_hash],
             where: "invite_token_hash IS NOT NULL"
           )

    create table(:maraca_concessoes) do
      add :tipo, :string, null: false
      add :recurso, :string, null: false
      add :concedida_em, :utc_datetime, null: false
      add :revogada_em, :utc_datetime
      add :public_id, :string, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :leitor_id, references(:maraca_avas), null: false
      add :dono_id, references(:maraca_avas), null: false

      timestamps(type: :utc_datetime)
    end

    # O nome e o que o ecto_sqlite3 sintetiza a partir das colunas no erro de
    # unicidade: SQLite nao reporta o nome do indice, e esse nome tambem casa
    # no Postgres.
    create unique_index(:maraca_concessoes, [:tekoa_id, :leitor_id, :tipo, :recurso],
             where: "revogada_em IS NULL",
             name: :maraca_concessoes_tekoa_id_leitor_id_tipo_recurso_index
           )

    create unique_index(:maraca_concessoes, [:public_id])
    create index(:maraca_concessoes, [:tekoa_id, :leitor_id])
    create index(:maraca_concessoes, [:tekoa_id, :dono_id])

    create table(:maraca_pedidos) do
      add :tipo, :string, null: false
      add :recurso, :string, null: false
      add :motivo, :string
      add :status, :string, null: false, default: "pendente"
      add :decidido_em, :utc_datetime
      add :public_id, :string, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :pedinte_id, references(:maraca_avas), null: false
      add :dono_id, references(:maraca_avas), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:maraca_pedidos, [:tekoa_id, :pedinte_id, :tipo, :recurso],
             where: "status = 'pendente'",
             name: :maraca_pedidos_tekoa_id_pedinte_id_tipo_recurso_index
           )

    create unique_index(:maraca_pedidos, [:public_id])
    create index(:maraca_pedidos, [:tekoa_id, :dono_id])

    create table(:maraca_tekoa_keys) do
      add :multibase, :string, null: false
      add :pub, :binary, null: false
      add :aposentada_em, :utc_datetime
      add :tekoa_id, references(:maraca_tekoas), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:maraca_tekoa_keys, [:tekoa_id])

    create table(:maraca_mural) do
      add :seq, :integer, null: false
      add :prev, :string
      add :tipo, :string, null: false
      add :payload, :map, null: false
      add :signature, :binary, null: false
      add :cid, :string, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:maraca_mural, [:tekoa_id, :seq])

    create table(:ybira_folders) do
      add :rkey, :string, null: false
      add :cid, :string, null: false
      add :nome, :string, null: false
      add :zona, :string, null: false, default: "casa"
      add :apagado_em, :utc_datetime
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :dono_id, references(:maraca_avas), null: false
      add :parent_id, references(:ybira_folders)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ybira_folders, [:tekoa_id, :rkey])
    create index(:ybira_folders, [:tekoa_id, :dono_id])
    create index(:ybira_folders, [:tekoa_id, :parent_id])

    create table(:ybira_files) do
      add :rkey, :string, null: false
      add :cid, :string, null: false
      add :blob_cid, :string, null: false
      add :nome, :string, null: false
      add :mime, :string, null: false
      add :tamanho, :integer, null: false
      add :hash, :string, null: false
      add :zona, :string, null: false, default: "casa"
      add :apagado_em, :utc_datetime
      add :tekoa_id, references(:maraca_tekoas), null: false
      add :dono_id, references(:maraca_avas), null: false
      add :folder_id, references(:ybira_folders)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:ybira_files, [:tekoa_id, :rkey])
    create index(:ybira_files, [:tekoa_id, :dono_id])
    create index(:ybira_files, [:tekoa_id, :folder_id])

    create table(:ybira_records) do
      add :rkey, :string, null: false
      add :collection, :string, null: false
      add :cid, :string, null: false
      add :record, :map, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:ybira_records, [:tekoa_id, :cid])
    create index(:ybira_records, [:tekoa_id, :collection, :rkey])

    create table(:ybira_blobs) do
      add :cid, :string, null: false
      add :tamanho, :integer, null: false
      add :hash, :string, null: false
      add :tekoa_id, references(:maraca_tekoas), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:ybira_blobs, [:tekoa_id, :cid])

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
