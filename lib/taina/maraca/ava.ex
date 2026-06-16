defmodule Taina.Maraca.Ava do
  @moduledoc """
  Representa uma pessoa que usa o Tainá dentro de uma comunidade.

  Cada Ava (pessoa) pertence a uma Tekoa (comunidade) e tem um papel: zelador(a)
  (cuida da máquina) ou morador(a) (qualquer membro). O nome vem do Tupi-Guarani
  e representa a essência de uma pessoa na comunidade digital.

  ## Identidade: nome-primeiro, sem e-mail (RFC_003, seção 4)

    * `username` - nome de usuário, único na comunidade. É a identidade e a chave
      de acesso (login por nome). Modelado como handle (minúsculas, sem espaços)
      para virar `nome@tekoa` na federação futura.
    * `display_name` - nome de exibição, opcional. Texto livre (espaços, acentos),
      é como o nome aparece para a comunidade. Trocá-lo nunca quebra o login.
    * `role` - papel na comunidade (`:zelador` ou `:morador`).
    * `activated_at` - quando a pessoa aceitou o convite e a conta ficou ativa.
    * `public_id` - identificador público seguro (não expõe o id do banco).
    * `password_hash` - hash bcrypt da senha.
    * `invite_token_hash` - hash SHA256 do token de convite (no banco).
    * `invite_token` - token cru do convite (virtual, vai no link/QR).
    * `reset_token_hash` / `reset_token` - idem para o link de redefinição que o
      zelador gera (recuperação mediada, RFC_003 seção 4).
    * `invited_by_id` / `invited_at` - quem convidou e quando.

  Não há e-mail: convites são por link/QR e a recuperação passa pelo zelador
  (RFC_002 D6, RFC_003 seção 4). A conta fica pendente até o aceite do convite,
  não até confirmar e-mail.

  ## Fluxos de autenticação

  Suportados por changesets específicos:

    1. **Convite** (`invitation_changeset/2`): cria um Ava pendente só com token
       de convite e papel. Sem nome, sem senha ainda.
    2. **Aceite do convite** (`accept_invite_changeset/2`): a pessoa define nome
       de usuário, nome de exibição (opcional) e senha; a conta ativa.
    3. **Pedido de redefinição** (`password_reset_request_changeset/1`): o
       zelador gera um token de redefinição.
    4. **Redefinição** (`password_reset_changeset/2`): a pessoa define a nova
       senha pelo link.

  ## Segurança

  - Senhas são hasheadas com bcrypt antes de armazenadas.
  - Tokens (convite e redefinição) são gerados com Nanoid (32 caracteres); só o
    hash SHA256 é persistido (defesa em profundidade). O token cru fica num campo
    virtual, usado apenas para montar o link/QR.
  - Verificação de token usa comparação de tempo constante.
  - Token de redefinição expira após 1 hora; token de convite, após 7 dias.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Taina.Maraca
  alias Taina.Repo.PublicId

  @type t :: %__MODULE__{
          id: integer() | nil,
          username: String.t() | nil,
          display_name: String.t() | nil,
          activated_at: DateTime.t() | nil,
          public_id: String.t() | nil,
          role: :zelador | :morador,
          password_hash: String.t() | nil,
          invite_token_hash: String.t() | nil,
          invite_sent_at: DateTime.t() | nil,
          reset_token_hash: String.t() | nil,
          reset_token_sent_at: DateTime.t() | nil,
          invited_at: DateTime.t() | nil,
          password: String.t() | nil,
          password_confirmation: String.t() | nil,
          invite_token: String.t() | nil,
          reset_token: String.t() | nil,
          tekoa_id: integer() | nil,
          tekoa: Maraca.Tekoa.t() | NotLoaded.t() | nil,
          invited_by_id: integer() | nil,
          invited_by: t() | NotLoaded.t() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  @schema_prefix "maraca"
  schema "avas" do
    field :username, :string
    field :display_name, :string
    field :activated_at, :utc_datetime_usec
    field :public_id, PublicId, autogenerate: true
    field :role, Ecto.Enum, values: ~w(zelador morador)a, default: :morador

    # Authentication fields
    field :password_hash, :string

    # Invite token (link/QR): the invite carries the token, no e-mail.
    field :invite_token_hash, :string
    field :invite_sent_at, :utc_datetime_usec

    # Password reset token (zelador-minted link)
    field :reset_token_hash, :string
    field :reset_token_sent_at, :utc_datetime_usec

    # Invitation tracking
    field :invited_at, :utc_datetime_usec

    # Virtual fields for password and token handling
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :invite_token, :string, virtual: true
    field :reset_token, :string, virtual: true

    belongs_to :tekoa, Maraca.Tekoa
    belongs_to :invited_by, Maraca.Ava

    timestamps()
  end

  @doc """
  Valida um Ava com nome de usuário e comunidade.

  ## Campos obrigatórios

    * `username` - 3 a 50 caracteres, handle (minúsculas, números, `.`, `-`, `_`)
    * `tekoa_id` - deve referenciar uma Tekoa existente

  ## Exemplos

      iex> changeset(%Ava{}, %{username: "maria", tekoa_id: 1})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Ava{}, %{username: "ab"})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(ava, attrs) do
    ava
    |> cast(attrs, [:username, :display_name, :role, :activated_at, :public_id, :tekoa_id])
    |> validate_required([:username, :tekoa_id])
    |> validate_username()
    |> validate_display_name()
    |> validate_inclusion(:role, ~w(zelador morador)a)
    |> unique_constraint(:username, name: :avas_tekoa_id_username_index)
    |> unique_constraint(:public_id)
  end

  @doc """
  Changeset para convite por um zelador.

  Cria um Ava pendente: só token de convite e papel, sem nome nem senha (a
  pessoa define no aceite). O convite não pede e-mail: o token viaja no link/QR.

  ## Campos obrigatórios

    * `tekoa_id` - comunidade à qual pertence
    * `invited_by_id` - id do zelador que está convidando

  ## Gerado automaticamente

    * `invite_token_hash` - hash SHA256 do token (no banco)
    * `invite_token` - token cru (campo virtual, use para montar o link/QR)
    * `invite_sent_at` / `invited_at` - timestamps do convite

  ## Exemplos

      iex> changeset = invitation_changeset(%Ava{}, %{tekoa_id: 1, invited_by_id: 2})
      iex> changeset.valid?
      true
      iex> changeset.changes.invite_token
      "abc123..." # token cru de 32 caracteres para o link/QR
  """
  def invitation_changeset(ava, attrs) do
    raw_token = generate_token()

    ava
    |> cast(attrs, [:tekoa_id, :invited_by_id, :role])
    |> validate_required([:tekoa_id, :invited_by_id])
    |> validate_inclusion(:role, ~w(zelador morador)a)
    |> put_change(:invite_token_hash, hash_token(raw_token))
    |> put_change(:invite_token, raw_token)
    |> put_change(:invite_sent_at, DateTime.utc_now())
    |> put_change(:invited_at, DateTime.utc_now())
    |> unique_constraint(:invite_token_hash)
  end

  @doc """
  Changeset de aceite do convite: a pessoa cria a conta.

  Define nome de usuário, nome de exibição (opcional) e senha; marca a conta como
  ativa (`activated_at`) e queima o token de convite.

  ## Campos obrigatórios

    * `username` - nome de usuário (handle, 3 a 50 caracteres)
    * `password` - senha (mínimo 8 caracteres)
    * `password_confirmation` - confirmação (deve ser igual)

  ## Opcionais

    * `display_name` - nome de exibição

  ## Exemplos

      iex> accept_invite_changeset(invited_ava, %{
      ...>   username: "maria",
      ...>   password: "senhasegura123",
      ...>   password_confirmation: "senhasegura123"
      ...> })
      %Ecto.Changeset{valid?: true}
  """
  def accept_invite_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:username, :display_name, :password, :password_confirmation])
    |> validate_required([:username, :password, :password_confirmation])
    |> validate_username()
    |> validate_display_name()
    |> validate_length(:password, min: 8, message: "deve ter no mínimo 8 caracteres")
    |> validate_confirmation(:password, message: "senha e confirmação não coincidem")
    |> hash_password()
    |> put_change(:activated_at, DateTime.utc_now())
    |> put_change(:invite_token_hash, nil)
    |> unique_constraint(:username, name: :avas_tekoa_id_username_index)
  end

  @doc """
  Changeset para o zelador pedir a redefinição de senha de uma pessoa.

  Gera um token de redefinição e o timestamp de envio. O token expira após 1
  hora. O zelador entrega o link pelo mesmo canal dos convites (RFC_003 seção 4).

  ## Efeitos

    * `reset_token_hash` - hash SHA256 do token (no banco)
    * `reset_token` - token cru (campo virtual, para montar o link)
    * `reset_token_sent_at` - timestamp do envio
  """
  def password_reset_request_changeset(ava) do
    raw_token = generate_token()

    ava
    |> change()
    |> put_change(:reset_token_hash, hash_token(raw_token))
    |> put_change(:reset_token, raw_token)
    |> put_change(:reset_token_sent_at, DateTime.utc_now())
    |> unique_constraint(:reset_token_hash)
  end

  @doc """
  Changeset para completar a redefinição de senha pelo link.

  Valida a nova senha, gera o hash e remove o token de redefinição.

  ## Campos obrigatórios

    * `password` - nova senha (mínimo 8 caracteres)
    * `password_confirmation` - confirmação da nova senha
  """
  def password_reset_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:password, :password_confirmation])
    |> validate_required([:password, :password_confirmation])
    |> validate_length(:password, min: 8, message: "deve ter no mínimo 8 caracteres")
    |> validate_confirmation(:password, message: "senha e confirmação não coincidem")
    |> hash_password()
    |> put_change(:reset_token_hash, nil)
    |> put_change(:reset_token_sent_at, nil)
  end

  @doc """
  Verifica se um token apresentado corresponde ao hash armazenado.

  Usa comparação de tempo constante para prevenir timing attacks.

  ## Exemplos

      iex> verify_token(ava.invite_token_hash, token_from_link)
      true

      iex> verify_token(ava.reset_token_hash, wrong_token)
      false
  """
  def verify_token(stored_hash, presented_token) when is_binary(stored_hash) and is_binary(presented_token) do
    presented_hash = hash_token(presented_token)
    Plug.Crypto.secure_compare(stored_hash, presented_hash)
  end

  def verify_token(nil, _presented_token), do: false
  def verify_token(_stored_hash, nil), do: false

  # O username é a chave de acesso e a semente do handle federado: normalizamos
  # para minúsculas e restringimos o conjunto de caracteres (sem espaços).
  defp validate_username(changeset) do
    changeset
    |> update_change(:username, &normalize_username/1)
    |> validate_length(:username, min: 3, max: 50)
    |> validate_format(:username, ~r/^[a-z0-9._-]+$/,
      message: "use só minúsculas, números, ponto, hífen ou _, sem espaços"
    )
  end

  defp normalize_username(nil), do: nil
  defp normalize_username(username), do: username |> String.trim() |> String.downcase()

  defp validate_display_name(changeset) do
    validate_length(changeset, :display_name, max: 80)
  end

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)
    |> delete_change(:password_confirmation)
  end

  defp hash_password(changeset), do: changeset

  defp generate_token do
    Nanoid.generate(32)
  end

  @doc """
  Hash SHA256 de um token cru, no mesmo formato persistido no banco.

  Usado pelo contexto Maraca para localizar Avas por token
  (`invite_token_hash` / `reset_token_hash`).
  """
  def hash_token(raw_token) do
    :sha256 |> :crypto.hash(raw_token) |> Base.encode64(padding: false)
  end
end
