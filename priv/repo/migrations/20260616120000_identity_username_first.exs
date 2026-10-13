defmodule Taina.Repo.Migrations.IdentityUsernameFirst do
  @moduledoc """
  RFC_003 seção 4: identidade nome-primeiro, e-mail descartado.

  - Renomeia os papéis no banco: admin -> zelador, member -> morador (D3). O
    enum é um `Ecto.Enum` sobre coluna `:string`, então basta um UPDATE.
  - Descarta a coluna `:email` e o índice único de e-mail.
  - Reaproveita o token de confirmação de e-mail como token de convite
    (`email_confirmation_*` -> `invite_*`); a mesma infra serve o convite e o
    link de redefinição do zelador.
  - `confirmed_at` -> `activated_at`: marca o aceite do convite, não a
    confirmação de e-mail.
  - Adiciona `:display_name` (nome de exibição, opcional).

  Pré-alpha (RFC_002/D2, RFC_003/D3): migração limpa, sem ressalva de
  compatibilidade de sessão.
  """

  use Ecto.Migration

  def up do
    # Papéis: admin -> zelador, member -> morador.
    execute "UPDATE avas SET role = 'zelador' WHERE role = 'admin'"
    execute "UPDATE avas SET role = 'morador' WHERE role = 'member'"

    # E-mail descartado.
    drop unique_index(:avas, [:tekoa_id, :email], name: :avas_tekoa_id_email_index)

    alter table(:avas) do
      remove :email
    end

    # Confirmação de e-mail -> token de convite (reaproveita a infra).
    drop unique_index(:avas, [:email_confirmation_token_hash])

    rename table(:avas), :email_confirmation_token_hash, to: :invite_token_hash
    rename table(:avas), :email_confirmation_sent_at, to: :invite_sent_at

    create unique_index(:avas, [:invite_token_hash], where: "invite_token_hash IS NOT NULL")

    # Aceite do convite, não confirmação de e-mail.
    rename table(:avas), :confirmed_at, to: :activated_at

    # Nome de exibição (opcional): o rosto social, separado da chave de acesso.
    alter table(:avas) do
      add :display_name, :string
    end
  end

  def down do
    alter table(:avas) do
      remove :display_name
    end

    rename table(:avas), :activated_at, to: :confirmed_at

    drop unique_index(:avas, [:invite_token_hash])

    rename table(:avas), :invite_token_hash, to: :email_confirmation_token_hash
    rename table(:avas), :invite_sent_at, to: :email_confirmation_sent_at

    create unique_index(:avas, [:email_confirmation_token_hash])

    alter table(:avas) do
      add :email, :string
    end

    create unique_index(:avas, [:tekoa_id, :email], name: :avas_tekoa_id_email_index)

    execute "UPDATE avas SET role = 'admin' WHERE role = 'zelador'"
    execute "UPDATE avas SET role = 'member' WHERE role = 'morador'"
  end
end
