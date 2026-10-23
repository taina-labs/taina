defmodule Ypy.Maraca.Pedido do
  @moduledoc """
  O pedido de acesso: um morador pede ao dono a leitura de um recurso da
  casa (RFC_003 D2). Nasce `:pendente`; o dono aprova (gera `Concessao`) ou
  nega. O pedido e mero intermediario: nao da acesso, registra o pedido.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Ypy.Maraca.Ava
  alias Ypy.Maraca.Tekoa
  alias Ypy.PublicId

  @tipos ["ypy.file.v0", "ypy.folder.v0"]
  @status [:pendente, :aprovado, :negado]

  @type t :: %__MODULE__{
          id: integer() | nil,
          tipo: String.t() | nil,
          recurso: String.t() | nil,
          motivo: String.t() | nil,
          status: :pendente | :aprovado | :negado,
          decidido_em: DateTime.t() | nil,
          public_id: String.t() | nil,
          tekoa_id: integer() | nil,
          pedinte_id: integer() | nil,
          dono_id: integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "maraca_pedidos" do
    field(:tipo, :string)
    field(:recurso, :string)
    field(:motivo, :string)
    field(:status, Ecto.Enum, values: @status, default: :pendente)
    field(:decidido_em, :utc_datetime)
    field(:public_id, PublicId, autogenerate: true)

    belongs_to(:tekoa, Tekoa)
    belongs_to(:pedinte, Ava)
    belongs_to(:dono, Ava)

    timestamps(type: :utc_datetime)
  end

  @doc "Cria o pedido pendente."
  def changeset(pedido, attrs) do
    pedido
    |> cast(attrs, [:tipo, :recurso, :motivo, :tekoa_id, :pedinte_id, :dono_id])
    |> validate_required([:tipo, :recurso, :tekoa_id, :pedinte_id, :dono_id])
    |> validate_inclusion(:tipo, @tipos)
    |> unique_constraint(:recurso,
      name: :maraca_pedidos_tekoa_id_pedinte_id_tipo_recurso_index,
      message: "ja existe pedido pendente deste recurso para este morador"
    )
    |> unique_constraint(:public_id)
  end

  @doc "A decisao do dono: :aprovado ou :negado, com o momento."
  def decide_changeset(pedido, status, agora) when status in [:aprovado, :negado] do
    change(pedido, status: status, decidido_em: agora)
  end
end
