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

  alias Ypy.Maraca.Credentials
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
    field(:username, :string)
    field(:display_name, :string)
    field(:papel, Ecto.Enum, values: [:zelador, :morador], default: :morador)
    field(:public_id, PublicId, autogenerate: true)
    field(:password_hash, :string)
    field(:activated_at, :utc_datetime)
    field(:invite_token_hash, :string)
    field(:invite_sent_at, :utc_datetime)
    field(:reset_token_hash, :string)
    field(:reset_sent_at, :utc_datetime)
    field(:invited_at, :utc_datetime)
    field(:deactivated_at, :utc_datetime)

    # A senha crua nunca toca o banco: virtual, so para o changeset hashear.
    field(:password, :string, virtual: true)

    belongs_to(:tekoa, Tekoa)
    belongs_to(:invited_by, __MODULE__)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria ou atualiza um Ava."
  def changeset(ava, attrs) do
    ava
    |> cast(attrs, [:username, :display_name, :papel])
    |> validate_required([:username, :tekoa_id])
    |> validate_username()
    |> validate_length(:display_name, max: 80)
    |> foreign_key_constraint(:tekoa_id)
    |> unique_constraint(:username, name: :maraca_avas_tekoa_id_username_index)
    |> unique_constraint(:public_id)
  end

  @doc """
  O convite: um ava pendente, so com token hashado, papel e quem convidou. O
  token cru (e o link) e trabalho do produto; daqui sai so o hash.
  """
  def invitation_changeset(ava, attrs) do
    ava
    |> cast(attrs, [
      :tekoa_id,
      :invited_by_id,
      :papel,
      :invite_token_hash,
      :invite_sent_at,
      :invited_at
    ])
    |> validate_required([:tekoa_id, :invited_by_id, :invite_token_hash])
    |> validate_inclusion(:papel, [:zelador, :morador])
    |> unique_constraint(:invite_token_hash)
  end

  @doc "O aceite do convite: nome de usuario, senha e a conta ativa."
  def accept_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:username, :display_name, :password])
    |> validate_required([:username, :password])
    |> validate_username()
    |> validate_length(:password, min: 8)
    |> hash_password()
    |> put_change(:activated_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> put_change(:invite_token_hash, nil)
    |> put_change(:invite_sent_at, nil)
    |> unique_constraint(:username, name: :maraca_avas_tekoa_id_username_index)
  end

  @doc "O pedido de redefinicao que o zelador gera (entrega e token no produto)."
  def reset_request_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:reset_token_hash, :reset_sent_at])
    |> validate_required([:reset_token_hash])
    |> unique_constraint(:reset_token_hash)
  end

  @doc "A redefinicao completa: nova senha e token queimado."
  def reset_changeset(ava, attrs) do
    ava
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8)
    |> hash_password()
    |> put_change(:reset_token_hash, nil)
    |> put_change(:reset_sent_at, nil)
  end

  @doc "Troca de papel. Quem pode e a protecao do ultimo zelador sao do contexto."
  def papel_changeset(ava, papel) do
    ava
    |> cast(%{papel: papel}, [:papel])
    |> validate_inclusion(:papel, [:zelador, :morador])
  end

  @doc "Desativa (DateTime) ou reativa (nil). Programatico, nunca de input."
  def deactivation_changeset(ava, deactivated_at) do
    change(ava, deactivated_at: deactivated_at)
  end

  @doc "Conta ativa? Desativada nao autentica e nao aparece como moradora."
  def active?(%__MODULE__{activated_at: at, deactivated_at: nil}), do: at != nil
  def active?(%__MODULE__{}), do: false

  defp hash_password(%Ecto.Changeset{valid?: true, changes: %{password: password}} = changeset) do
    changeset
    |> put_change(:password_hash, Credentials.hash(password))
    |> delete_change(:password)
  end

  defp hash_password(changeset), do: changeset

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
