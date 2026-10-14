defmodule Taina.Maraca.DeviceToken do
  @moduledoc """
  O token de dispositivo (RFC_005 secao 4): o irmao mobile da sessao Phoenix.

  O segredo cru (`tnd_` mais 32 caracteres) aparece uma unica vez, na
  criacao; no banco so o hash SHA-256, no mesmo formato de convite e reset.
  Sem expiracao nem teto de dispositivos: a revogacao (pela dona ou pela
  zeladora) e o ciclo de vida.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.PublicId

  @type t :: %__MODULE__{
          id: integer() | nil,
          name: String.t() | nil,
          public_id: String.t() | nil,
          token_hash: String.t() | nil,
          last_used_at: DateTime.t() | nil,
          revoked_at: DateTime.t() | nil,
          ava_id: integer() | nil,
          tekoa_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "maraca_device_tokens" do
    field :name, :string
    field :public_id, PublicId, autogenerate: true
    field :token_hash, :string
    field :last_used_at, :utc_datetime
    field :revoked_at, :utc_datetime

    belongs_to :ava, Ava
    belongs_to :tekoa, Tekoa

    timestamps(type: :utc_datetime)
  end

  @doc """
  O rotulo do dispositivo (1 a 80). O dono e a Tekoa sao do contexto: entram
  explicitamente na struct, nunca de input.
  """
  def changeset(device_token, attrs) do
    device_token
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 80)
  end
end
