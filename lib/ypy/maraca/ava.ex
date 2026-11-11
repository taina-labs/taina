defmodule Ypy.Maraca.Ava do
  @moduledoc """
  A pessoa dentro de uma Tekoa: `username` e a chave de acesso (a parte
  `nome` do handle `nome@tekoa`), `papel` e o papel social (`:zelador` cuida
  da maquina, `:morador` e membro comum).

  As colunas de ava pendente e de token (convite e reset) e o hash de senha
  sao substantivos e invariantes do kernel (RFC_006 secao 9); os fluxos que
  as giram (convite, login, entrega de reset) ficam no produto.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Tekoa
  alias Ypy.PublicId

  @username_format ~r/^[a-z0-9._-]+$/

  @type t :: %__MODULE__{
          id: integer() | nil,
          username: String.t() | nil,
          display_name: String.t() | nil,
          papel: :zelador | :morador,
          public_id: String.t() | nil,
          password_hash: String.t() | nil,
          activated_at: DateTime.t() | nil,
          invite_token_hash: String.t() | nil,
          invite_sent_at: DateTime.t() | nil,
          reset_token_hash: String.t() | nil,
          reset_sent_at: DateTime.t() | nil,
          invited_at: DateTime.t() | nil,
          deactivated_at: DateTime.t() | nil,
          tekoa_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "maraca_avas" do
    field(:activated_at, :utc_datetime)
    field(:deactivated_at, :utc_datetime)
    field(:display_name, :string)
    field(:invite_sent_at, :utc_datetime)
    field(:invite_token_hash, :string)
    field(:invited_at, :utc_datetime)
    belongs_to(:invited_by, __MODULE__)
    field(:papel, Ecto.Enum, values: [:zelador, :morador], default: :morador)

    # A senha crua nunca toca o banco: virtual, so para o changeset hashear.
    field(:password, :string, virtual: true)
    field(:password_hash, :string)
    field(:public_id, PublicId, autogenerate: true)
    field(:reset_sent_at, :utc_datetime)
    field(:reset_token_hash, :string)

    belongs_to(:tekoa, Tekoa)
    field(:username, :string)

    timestamps(type: :utc_datetime)
  end

  @doc "O aceite do convite: nome de usuario, senha e a conta ativa."
  def accept_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:display_name, :password, :username])
    |> validate_required([:password, :username])
    |> validate_username()
    |> validate_length(:password, min: 8)
    |> maybe_hash_password()
    |> put_change(:activated_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> put_change(:invite_token_hash, nil)
    |> put_change(:invite_sent_at, nil)
    |> unique_constraint(:username, name: :maraca_avas_tekoa_id_username_index)
  end

  @doc "Conta ativa? Desativada nao autentica e nao aparece como moradora."
  def active?(%__MODULE__{activated_at: at, deactivated_at: nil}), do: at != nil
  def active?(%__MODULE__{}), do: false

  @doc "Cria ou atualiza um Ava."
  def changeset(ava, attrs) do
    ava
    |> cast(attrs, [:display_name, :papel, :username])
    |> validate_required([:username, :tekoa_id])
    |> validate_username()
    |> validate_length(:display_name, max: 80)
    |> foreign_key_constraint(:tekoa_id)
    |> unique_constraint(:username, name: :maraca_avas_tekoa_id_username_index)
    |> unique_constraint(:public_id)
  end

  @doc "Desativa (DateTime) ou reativa (nil). Programatico, nunca de input."
  def deactivation_changeset(ava, deactivated_at) do
    change(ava, deactivated_at: deactivated_at)
  end

  @doc """
  O convite: um ava pendente, so com token hashado, papel e quem convidou. O
  token cru (e o link) e trabalho do produto; daqui sai so o hash.
  """
  def invitation_changeset(ava, attrs) do
    ava
    |> cast(attrs, [
      :invite_sent_at,
      :invite_token_hash,
      :invited_at,
      :invited_by_id,
      :papel,
      :tekoa_id
    ])
    |> validate_required([:invite_token_hash, :invited_by_id, :tekoa_id])
    |> validate_inclusion(:papel, [:zelador, :morador])
    |> unique_constraint(:invite_token_hash)
  end

  @doc "Troca de papel. Quem pode e a protecao do ultimo zelador sao do contexto."
  def papel_changeset(ava, papel) do
    ava
    |> cast(%{papel: papel}, [:papel])
    |> validate_inclusion(:papel, [:zelador, :morador])
  end

  @doc "A redefinicao completa: nova senha e token queimado."
  def reset_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8)
    |> maybe_hash_password()
    |> put_change(:reset_token_hash, nil)
    |> put_change(:reset_sent_at, nil)
  end

  @doc "O pedido de redefinicao que o zelador gera (entrega e token no produto)."
  def reset_request_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:reset_token_hash, :reset_sent_at])
    |> validate_required([:reset_token_hash])
    |> unique_constraint(:reset_token_hash)
  end

  defp maybe_hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
    |> delete_change(:password)
  end

  defp maybe_hash_password(changeset), do: changeset

  defp validate_username(changeset) do
    changeset
    |> update_change(:username, fn
      nil -> nil
      username -> username |> String.trim() |> String.downcase()
    end)
    |> validate_length(:username, min: 3, max: 50)
    |> validate_format(:username, @username_format, message: "use so minusculas, numeros, ponto, hifen ou underline")
  end
end
