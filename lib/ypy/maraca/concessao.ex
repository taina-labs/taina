defmodule Ypy.Maraca.Concessao do
  @moduledoc """
  A permissao de leitura explicita (RFC_003 D2): o dono abre a propria casa
  para um leitor especifico, e vale para o zelador como para qualquer
  morador. Ativa enquanto `revogada_em` for nil; revogar nao apaga, porque a
  concessao e um fato social.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.PublicId

  @tipos ["ypy.file.v0", "ypy.folder.v0"]

  @type t :: %__MODULE__{
          id: integer() | nil,
          tipo: String.t() | nil,
          recurso: String.t() | nil,
          concedida_em: DateTime.t() | nil,
          revogada_em: DateTime.t() | nil,
          public_id: String.t() | nil,
          tekoa_id: integer() | nil,
          leitor_id: integer() | nil,
          dono_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "maraca_concessoes" do
    field(:tipo, :string)
    field(:recurso, :string)
    field(:concedida_em, :utc_datetime)
    field(:revogada_em, :utc_datetime)
    field(:public_id, PublicId, autogenerate: true)

    belongs_to(:tekoa, Tekoa)
    belongs_to(:leitor, Ava)
    belongs_to(:dono, Ava)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria uma concessao ativa. Quem pode conceder e guarda o contexto."
  def changeset(concessao, attrs) do
    concessao
    |> cast(attrs, [:tipo, :recurso, :concedida_em, :tekoa_id, :leitor_id, :dono_id])
    |> validate_required([:tipo, :recurso, :concedida_em, :tekoa_id, :leitor_id, :dono_id])
    |> validate_inclusion(:tipo, @tipos)
    |> unique_constraint(:recurso,
      name: :maraca_concessoes_tekoa_id_leitor_id_tipo_recurso_index,
      message: "ja existe concessao ativa deste recurso para este leitor"
    )
    |> unique_constraint(:public_id)
  end

  @doc "Revoga: aposenta a concessao, sem apagar o fato."
  def revoke_changeset(concessao, agora) do
    change(concessao, revogada_em: agora)
  end
end
