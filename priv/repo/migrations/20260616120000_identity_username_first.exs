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
    execute "UPDATE maraca.avas SET role = 'zelador' WHERE role = 'admin'"
    execute "UPDATE maraca.avas SET role = 'morador' WHERE role = 'member'"

    # E-mail descartado.
    drop unique_index(:avas, [:tekoa_id, :email],
           prefix: "maraca",
           name: :avas_tekoa_id_email_index
         )

    alter table(:avas, prefix: "maraca") do
      remove :email
    end

    # Confirmação de e-mail -> token de convite (reaproveita a infra).
    drop unique_index(:avas, [:email_confirmation_token_hash], prefix: "maraca")

    rename table(:avas, prefix: "maraca"), :email_confirmation_token_hash, to: :invite_token_hash
    rename table(:avas, prefix: "maraca"), :email_confirmation_sent_at, to: :invite_sent_at

    create unique_index(:avas, [:invite_token_hash],
             prefix: "maraca",
             where: "invite_token_hash IS NOT NULL"
           )

    # Aceite do convite, não confirmação de e-mail.
    rename table(:avas, prefix: "maraca"), :confirmed_at, to: :activated_at

    # Nome de exibição (opcional): o rosto social, separado da chave de acesso.
    alter table(:avas, prefix: "maraca") do
      add :display_name, :string
    end
  end

  def down do
    alter table(:avas, prefix: "maraca") do
      remove :display_name
    end

    rename table(:avas, prefix: "maraca"), :activated_at, to: :confirmed_at

    drop unique_index(:avas, [:invite_token_hash], prefix: "maraca")

    rename table(:avas, prefix: "maraca"), :invite_token_hash, to: :email_confirmation_token_hash
    rename table(:avas, prefix: "maraca"), :invite_sent_at, to: :email_confirmation_sent_at

    create unique_index(:avas, [:email_confirmation_token_hash], prefix: "maraca")

    alter table(:avas, prefix: "maraca") do
      add :email, :string
    end

    create unique_index(:avas, [:tekoa_id, :email],
             prefix: "maraca",
             name: :avas_tekoa_id_email_index
           )

    execute "UPDATE maraca.avas SET role = 'admin' WHERE role = 'zelador'"
    execute "UPDATE maraca.avas SET role = 'member' WHERE role = 'morador'"
  end
end
