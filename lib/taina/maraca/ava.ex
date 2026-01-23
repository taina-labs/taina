defmodule Taina.Maraca.Ava do
  @moduledoc """
  Representa uma pessoa que usa o Tainá dentro de uma comunidade.

  Cada Ava (pessoa/usuário) pertence a uma Tekoa (comunidade) e pode ter diferentes
  níveis de permissão: admin (administrador) ou member (membro). O nome vem do Tupi-Guarani
  e representa a essência de uma pessoa na comunidade digital.

  ## Campos principais

    * `username` - Nome de usuário único dentro da comunidade
    * `email` - Email para comunicação e login
    * `role` - Função na comunidade (admin ou member)
    * `confirmed_at` - Data/hora em que o email foi confirmado
    * `public_id` - Identificador público seguro (não expõe o ID do banco)
    * `password_hash` - Hash bcrypt da senha do usuário
    * `email_confirmation_token_hash` - Hash SHA256 do token de confirmação (armazenado no DB)
    * `email_confirmation_token` - Token cru para confirmação (virtual, usado apenas em emails)
    * `reset_token_hash` - Hash SHA256 do token de reset (armazenado no DB)
    * `reset_token` - Token cru para reset de senha (virtual, usado apenas em emails)
    * `invited_by_id` - ID do Ava (admin) que convidou este usuário
    * `invited_at` - Data/hora do convite

  ## Fluxos de Autenticação

  Este schema suporta os seguintes fluxos através de changesets específicos:

  ### 1. Convite de Usuário (Admin)

      iex> changeset = Ava.invitation_changeset(%Ava{}, %{
      ...>   email: "novo@example.com",
      ...>   tekoa_id: 1,
      ...>   invited_by_id: admin.id
      ...> })

  ### 2. Confirmação de Email e Ativação

      iex> changeset = Ava.confirmation_changeset(invited_ava, %{
      ...>   username: "maria",
      ...>   password: "senhasegura123",
      ...>   password_confirmation: "senhasegura123"
      ...> })

  ### 3. Solicitação de Reset de Senha

      iex> changeset = Ava.password_reset_request_changeset(ava)

  ### 4. Completar Reset de Senha

      iex> changeset = Ava.password_reset_changeset(ava, %{
      ...>   password: "novasenha123",
      ...>   password_confirmation: "novasenha123"
      ...> })

  ## Segurança

  - Senhas são sempre hasheadas com bcrypt antes de serem armazenadas
  - Tokens de confirmação e reset são gerados usando Nanoid (32 caracteres)
  - Apenas o hash SHA256 dos tokens é armazenado no banco (defesa em profundidade)
  - Tokens crus são retornados em campos virtuais apenas para envio de email
  - Verificação de tokens usa comparação de tempo constante (previne timing attacks)
  - Token de reset expira após 1 hora
  - Email deve ser confirmado antes do primeiro login
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ecto.Association.NotLoaded
  alias Taina.Maraca
  alias Taina.Repo.PublicId

  @type t :: %__MODULE__{
          id: integer() | nil,
          username: String.t() | nil,
          email: String.t(),
          confirmed_at: DateTime.t() | nil,
          public_id: String.t() | nil,
          role: :admin | :member,
          password_hash: String.t() | nil,
          email_confirmation_token_hash: String.t() | nil,
          email_confirmation_sent_at: DateTime.t() | nil,
          reset_token_hash: String.t() | nil,
          reset_token_sent_at: DateTime.t() | nil,
          invited_at: DateTime.t() | nil,
          password: String.t() | nil,
          password_confirmation: String.t() | nil,
          email_confirmation_token: String.t() | nil,
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
    field :email, :string
    field :confirmed_at, :utc_datetime_usec
    field :public_id, PublicId, autogenerate: true
    field :role, Ecto.Enum, values: ~w(admin member)a, default: :member

    # Authentication fields
    field :password_hash, :string
    field :email_confirmation_token_hash, :string
    field :email_confirmation_sent_at, :utc_datetime_usec

    # Password reset fields
    field :reset_token_hash, :string
    field :reset_token_sent_at, :utc_datetime_usec

    # Invitation tracking
    field :invited_at, :utc_datetime_usec

    # Virtual fields for password and token handling
    field :password, :string, virtual: true
    field :password_confirmation, :string, virtual: true
    field :email_confirmation_token, :string, virtual: true
    field :reset_token, :string, virtual: true

    belongs_to :tekoa, Maraca.Tekoa
    belongs_to :invited_by, Maraca.Ava

    timestamps()
  end

  @doc """
  Valida um Ava com as informações fornecidas.

  ## Campos obrigatórios

    * `username` - deve ter entre 3 e 50 caracteres
    * `email` - deve ser um email válido e único na comunidade
    * `tekoa_id` - deve referenciar uma Tekoa existente

  ## Exemplos

      iex> changeset(%Ava{}, %{username: "maria", email: "maria@example.com", tekoa_id: 1})
      %Ecto.Changeset{valid?: true}

      iex> changeset(%Ava{}, %{username: "ab", email: "invalido"})
      %Ecto.Changeset{valid?: false}
  """
  def changeset(ava, attrs) do
    ava
    |> cast(attrs, [:username, :email, :role, :confirmed_at, :public_id, :tekoa_id])
    |> validate_required([:username, :email, :tekoa_id])
    |> validate_length(:username, min: 3, max: 50)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "deve ser um email válido")
    |> unique_constraint(:email, name: :avas_tekoa_id_email_index)
    |> unique_constraint(:username, name: :avas_tekoa_id_username_index)
    |> validate_inclusion(:role, ~w(admin member)a)
    |> unique_constraint(:public_id)
  end

  @doc """
  Changeset para convite de usuário por um administrador.

  Cria um novo Ava não confirmado com token de confirmação de email.
  Usado no fluxo: Admin convida → Email enviado → Usuário confirma

  ## Campos obrigatórios

    * `email` - Email do usuário convidado
    * `tekoa_id` - Comunidade à qual pertence
    * `invited_by_id` - ID do admin que está convidando

  ## Gerado automaticamente

    * `email_confirmation_token_hash` - Hash SHA256 do token (armazenado no DB)
    * `email_confirmation_token` - Token cru (campo virtual, use para enviar no email)
    * `email_confirmation_sent_at` - Timestamp do envio do convite
    * `invited_at` - Timestamp do convite

  ## Segurança

  O token cru é gerado usando Nanoid (32 caracteres) e apenas o hash SHA256
  é persistido no banco. O token cru fica disponível no campo virtual
  `email_confirmation_token` do changeset para ser usado no email.

  ## Exemplos

      iex> changeset = invitation_changeset(%Ava{}, %{
      ...>   email: "novo@example.com",
      ...>   tekoa_id: 1,
      ...>   invited_by_id: 2
      ...> })
      iex> changeset.valid?
      true
      iex> changeset.changes.email_confirmation_token
      "abc123..." # Token cru de 32 caracteres para usar no email
  """
  def invitation_changeset(ava, attrs) do
    raw_token = generate_token()

    ava
    |> cast(attrs, [:email, :tekoa_id, :invited_by_id, :role])
    |> validate_required([:email, :tekoa_id, :invited_by_id])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "deve ser um email válido")
    |> put_change(:email_confirmation_token_hash, hash_token(raw_token))
    |> put_change(:email_confirmation_token, raw_token)
    |> put_change(:email_confirmation_sent_at, DateTime.utc_now())
    |> put_change(:invited_at, DateTime.utc_now())
    |> unique_constraint(:email, name: :avas_tekoa_id_email_index)
    |> unique_constraint(:email_confirmation_token_hash)
  end

  @doc """
  Changeset para confirmação de email e ativação de conta.

  Usado quando o usuário clica no link de confirmação e define sua senha.
  Valida token, define username/senha, e marca email como confirmado.

  ## Campos obrigatórios

    * `username` - Nome de usuário (3-50 caracteres)
    * `password` - Senha (mínimo 8 caracteres)
    * `password_confirmation` - Confirmação da senha (deve ser igual)

  ## Efeitos

    * Hash da senha é gerado e armazenado em `password_hash`
    * `confirmed_at` é definido com timestamp atual
    * `email_confirmation_token_hash` é removido (null)

  ## Exemplos

      iex> confirmation_changeset(invited_ava, %{
      ...>   username: "maria",
      ...>   password: "senhasegura123",
      ...>   password_confirmation: "senhasegura123"
      ...> })
      %Ecto.Changeset{valid?: true}
  """
  def confirmation_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:username, :password, :password_confirmation])
    |> validate_required([:username, :password, :password_confirmation])
    |> validate_length(:username, min: 3, max: 50)
    |> validate_length(:password, min: 8, message: "deve ter no mínimo 8 caracteres")
    |> validate_confirmation(:password, message: "senha e confirmação não coincidem")
    |> hash_password()
    |> put_change(:confirmed_at, DateTime.utc_now())
    |> put_change(:email_confirmation_token_hash, nil)
    |> unique_constraint(:username, name: :avas_tekoa_id_username_index)
  end

  @doc """
  Changeset para solicitar reset de senha.

  Gera um token de reset e define o timestamp de envio.
  O token expira após 1 hora.

  ## Efeitos

    * `reset_token_hash` - Hash SHA256 do token (armazenado no DB)
    * `reset_token` - Token cru (campo virtual, use para enviar no email)
    * `reset_token_sent_at` - Timestamp do envio

  ## Segurança

  O token cru é gerado usando Nanoid (32 caracteres) e apenas o hash SHA256
  é persistido no banco. O token cru fica disponível no campo virtual
  `reset_token` do changeset para ser usado no email.

  ## Exemplos

      iex> changeset = password_reset_request_changeset(ava)
      iex> changeset.valid?
      true
      iex> changeset.changes.reset_token
      "xyz789..." # Token cru de 32 caracteres para usar no email
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
  Changeset para completar reset de senha.

  Valida nova senha, gera hash, e remove token de reset.

  ## Campos obrigatórios

    * `password` - Nova senha (mínimo 8 caracteres)
    * `password_confirmation` - Confirmação da nova senha

  ## Efeitos

    * `password_hash` é atualizado
    * `reset_token_hash` é removido (null)
    * `reset_token_sent_at` é removido (null)

  ## Exemplos

      iex> password_reset_changeset(ava, %{
      ...>   password: "novasenha123",
      ...>   password_confirmation: "novasenha123"
      ...> })
      %Ecto.Changeset{valid?: true}
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

  ## Parâmetros

    * `stored_hash` - Hash SHA256 armazenado no banco
    * `presented_token` - Token cru apresentado pelo usuário

  ## Exemplos

      iex> verify_token(ava.email_confirmation_token_hash, token_from_email)
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

  defp hash_token(raw_token) do
    :sha256 |> :crypto.hash(raw_token) |> Base.encode64(padding: false)
  end
end
