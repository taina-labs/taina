defmodule Ypy.Wire.Ava do
  @moduledoc """
  A pessoa no fio (RFC_005 secao 9, pessoas): o que a API devolve de um
  morador, sem hash de token nenhum. O estado pendente aparece so como
  ausencia de `activated_at`; tokens de convite e reset sao do produto e
  nunca entram na forma.
  """

  alias Ypy.Maraca.Ava
  alias Ypy.Wire

  @doc "O mapa JSON do ava: a palavra do dominio no `papel`, momentos em ISO-8601 UTC."
  @spec json(Ava.t()) :: map()
  def json(%Ava{} = ava) do
    %{
      "public_id" => ava.public_id,
      "username" => ava.username,
      "display_name" => ava.display_name,
      "papel" => papel(ava.papel),
      "activated_at" => Wire.at(ava.activated_at),
      "deactivated_at" => Wire.at(ava.deactivated_at),
      "created_at" => Wire.at(ava.inserted_at)
    }
  end

  defp papel(:zelador), do: "zelador"
  defp papel(:morador), do: "morador"
end
