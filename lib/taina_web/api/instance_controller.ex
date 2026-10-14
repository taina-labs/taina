defmodule TainaWeb.API.InstanceController do
  @moduledoc """
  A instancia (RFC_005 secao 9): quem e a comunidade e se a caixa ja foi criada.

  Publico, sem auth: e o que a tela de setup do app usa para saber se o
  endereco que a pessoa informou e um Taina.
  """

  use TainaWeb, :controller

  alias Taina.Maraca
  alias TainaWeb.API.Serializer

  def show(conn, _params) do
    tekoa =
      case Maraca.get_tekoa() do
        {:ok, tekoa} -> tekoa
        {:error, :not_bootstrapped} -> nil
      end

    json(conn, Serializer.instance(Maraca.bootstrapped?(), tekoa))
  end
end
