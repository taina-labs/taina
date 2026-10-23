defmodule Ypy.Maraca.Tekoa do
  @moduledoc """
  A comunidade: uma por caixa no box, N no hospedado (RFC_006 D11). A
  identidade e o `did:web` derivado do `domain` (`Ypy.Did.from_domain/1`); a
  trava de uma-Tekoa-por-box e politica do produto, nao invariante daqui.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Handle
  alias Ypy.PublicId

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          domain: String.t() | nil,
          public_id: String.t() | nil,
          settings: map(),
          storage_quota_bytes: integer() | nil,
          storage_used_bytes: integer(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "maraca_tekoas" do
    field(:name, :string)
    field(:domain, :string)
    field(:public_id, PublicId, autogenerate: true)
    field(:settings, :map, default: %{})
    field(:storage_quota_bytes, :integer)
    field(:storage_used_bytes, :integer, default: 0)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria ou atualiza uma Tekoa. Cota nil e ilimitada."
  def changeset(tekoa, attrs) do
    tekoa
    |> cast(attrs, [:name, :domain, :settings, :storage_quota_bytes])
    |> validate_required([:name, :domain])
    |> validate_length(:name, min: 3, max: 100)
    |> validate_number(:storage_quota_bytes, greater_than: 0)
    |> validate_domain()
    |> unique_constraint(:domain)
    |> unique_constraint(:public_id)
  end

  defp validate_domain(changeset) do
    if domain = get_field(changeset, :domain) do
      if Handle.valid_domain?(domain),
        do: changeset,
        else: add_error(changeset, :domain, "nao e um dominio valido de Tekoa")
    else
      changeset
    end
  end
end
