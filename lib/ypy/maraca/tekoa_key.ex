defmodule Ypy.Maraca.TekoaKey do
  @moduledoc """
  A chave publica da Tekoa, a que assina a cadeia e habita o documento DID.

  A chave privada fica no `Ypy.KeyStore` do produto; aqui mora so a publica,
  com a aposentadoria explicita (`aposentada_em`): a rotacao adiciona uma
  chave nova e aposenta a antiga, sem apagar fato nenhum.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Tekoa
  alias Ypy.Secp256k1

  @type t :: %__MODULE__{
          id: integer() | nil,
          multibase: String.t() | nil,
          pub: binary() | nil,
          aposentada_em: DateTime.t() | nil,
          tekoa_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "maraca_tekoa_keys" do
    field(:multibase, :string)
    field(:pub, :binary)
    field(:aposentada_em, :utc_datetime)

    belongs_to(:tekoa, Tekoa)

    timestamps(type: :utc_datetime)
  end

  @doc "Registra a chave publica ativa de uma Tekoa."
  def changeset(key, attrs) do
    key
    |> cast(attrs, [:pub, :multibase, :aposentada_em, :tekoa_id])
    |> validate_required([:pub, :multibase, :tekoa_id])
    |> foreign_key_constraint(:tekoa_id)
  end

  @doc "Aposenta a chave (a nova assume)."
  def retire_changeset(key, agora) do
    change(key, aposentada_em: agora)
  end

  @doc "`publicKeyMultibase` para a chave publica comprimida."
  def multibase(pub) when is_binary(pub), do: Secp256k1.public_key_multibase(pub)
end
