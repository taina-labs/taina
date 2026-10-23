defmodule Ypy.Record do
  @moduledoc """
  O envelope de record: o dado que a Tekoa assina por conteudo e endereca.

  Leva `$type` (a colecao, um NSID), `rkey` (o TID, id publico do item),
  `actor` (o handle de quem o criou), `created_at` (microssegundos, inteiro,
  para o CBOR ser deterministico) e o payload validado contra o lexicon. No
  fio DAG-CBOR os campos de controle andam no nivel de cima e o payload
  aninha em `"payload"`, o unico arranjo em que um campo de payload com o
  nome de um campo de controle nao pode colidir.

  A assinatura nao mora aqui: envelopes sao enderecados por conteudo e
  copiados, e assinaturas sao fatos ordenados pela cadeia (RFC_006 secao 6).
  A chave da Tekoa assina a entrada do mural que alcancou o envelope.

  `encode/1` e deterministico: o mesmo envelope, montado duas vezes a partir
  de entradas em ordens diferentes, da os mesmos bytes e o mesmo CIDv1, com
  as chaves ordenadas por tamanho e depois bytewise.
  """

  alias Ypy.Cbor
  alias Ypy.Cid
  alias Ypy.Lexicon.Validate

  @enforce_keys [:type, :rkey, :actor, :created_at, :payload]
  defstruct [:type, :rkey, :actor, :created_at, :payload]

  @typedoc "O envelope de record."
  @type t :: %__MODULE__{
          type: String.t(),
          rkey: String.t(),
          actor: String.t(),
          created_at: integer(),
          payload: map()
        }

  # A forma do envelope no fio, checada com o mesmo validador dos lexicons.
  @envelope_schema %{
    "type" => "object",
    "required" => ["$type", "rkey", "actor", "created_at", "payload"],
    "properties" => %{
      "$type" => %{"type" => "string", "format" => "nsid"},
      "rkey" => %{"type" => "string", "format" => "tid"},
      "actor" => %{"type" => "string", "format" => "handle"},
      "created_at" => %{"type" => "integer", "minimum" => 0},
      "payload" => %{"type" => "object"}
    }
  }

  @doc """
  Monta o envelope a partir de attrs, em qualquer ordem: :type, :rkey, :actor,
  :created_at e :payload, todos obrigatorios.

  Nao valida tipos: montar e juntar dados, e quem julga e o check/2, com a
  forma do envelope e o payload contra o lexicon. Chave de fora ou faltante
  levanta.
  """
  @spec build(keyword()) :: t()
  def build(attrs) when is_list(attrs) do
    struct!(__MODULE__, Map.new(attrs))
  end

  @doc """
  Confere o envelope contra o schema do lexicon da colecao: a forma dos
  campos de controle mais o payload contra as regras do lexicon.

  Devolve :ok ou {:error, erros}, com os erros do payload prefixados por
  `payload` no caminho, de modo que um caminho sozinho localiza o deslize no
  envelope inteiro. O schema e o schema resolvido da colecao; nil responde
  :unknown_collection, porque colecao desconhecida nao e erro de forma.
  """
  @spec check(t(), map() | nil) :: :ok | {:error, :unknown_collection} | {:error, [term()]}
  def check(_record, nil), do: {:error, :unknown_collection}

  def check(%__MODULE__{} = record, schema) when is_map(schema) do
    envelope_errors =
      case Validate.validate(@envelope_schema, to_wire(record)) do
        :ok -> []
        {:error, errors} -> errors
      end

    payload_errors =
      case Validate.validate(schema, record.payload) do
        :ok ->
          []

        {:error, errors} ->
          Enum.map(errors, fn {path, reason} -> {["payload" | path], reason} end)
      end

    case envelope_errors ++ payload_errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc "Os bytes DAG-CBOR canonicos do envelope e o CIDv1 deles."
  @spec encode(t()) :: {binary(), Cid.t()}
  def encode(%__MODULE__{} = record) do
    bytes = Cbor.encode(to_wire(record))
    {bytes, Cid.from_data(bytes)}
  end

  @doc "Decodifica bytes de volta ao envelope: {:ok, record} ou {:error, :malformed}."
  @spec decode(binary()) :: {:ok, t()} | {:error, :malformed}
  def decode(bytes) when is_binary(bytes) do
    case safe_decode(bytes) do
      {:ok, wire} -> from_wire(wire)
      :error -> {:error, :malformed}
    end
  end

  defp safe_decode(bytes) do
    {:ok, Cbor.decode!(bytes)}
  rescue
    ArgumentError -> :error
    MatchError -> :error
  end

  defp from_wire(
         %{"$type" => type, "rkey" => rkey, "actor" => actor, "created_at" => created_at, "payload" => payload} = wire
       ) do
    if envelope_ok?(wire, type, rkey, actor, created_at, payload) do
      {:ok, %__MODULE__{type: type, rkey: rkey, actor: actor, created_at: created_at, payload: payload}}
    else
      {:error, :malformed}
    end
  end

  defp from_wire(_), do: {:error, :malformed}

  defp envelope_ok?(wire, type, rkey, actor, created_at, payload) do
    map_size(wire) == 5 and is_binary(type) and is_binary(rkey) and is_binary(actor) and
      is_integer(created_at) and
      is_map(payload)
  end

  defp to_wire(%__MODULE__{} = record) do
    %{
      "$type" => record.type,
      "rkey" => record.rkey,
      "actor" => record.actor,
      "created_at" => record.created_at,
      "payload" => record.payload
    }
  end
end
