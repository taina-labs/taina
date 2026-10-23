defmodule Ypy.Wire.Mural do
  @moduledoc """
  A entrada do mural no fio: a projecao legivel da cadeia unica (RFC_006
  secao 8), com as coordenadas dela (`seq`, `cid`, `prev`) e o payload
  social tal como a cadeia o guarda.

  A assinatura crua nao vai: e material de verificacao da cadeia, do mundo
  da exportacao e da federacao, nao fato para quem le o mural.
  """

  alias Ypy.Mural.Entry
  alias Ypy.Wire

  @doc "O mapa JSON da entrada."
  @spec json(Entry.t()) :: map()
  def json(%Entry{} = entry) do
    %{
      "seq" => entry.seq,
      "tipo" => entry.tipo,
      "payload" => entry.payload,
      "cid" => entry.cid,
      "prev" => entry.prev,
      "created_at" => Wire.at(entry.inserted_at)
    }
  end
end
